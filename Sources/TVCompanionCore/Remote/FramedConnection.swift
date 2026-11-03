import Foundation
import Network
import Security

/// A TLS connection to the TV that carries varint length-prefixed protobuf messages.
@MainActor
final class FramedConnection {
    private let connection: NWConnection
    private var buffer = Data()
    private var queued: [Data] = []
    private var waiter: (id: UUID, continuation: CheckedContinuation<Data, Error>)?
    private var opening: CheckedContinuation<Void, Error>?
    private var closed = false
    private let peer: PeerCertificate

    var serverCertificate: SecCertificate? { peer.certificate }

    var onMessage: ((Data) -> Void)? {
        didSet { flushQueued() }
    }
    var onClose: (() -> Void)?

    init(host: String, port: UInt16, identity: RemoteIdentity) {
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        if let localIdentity = sec_identity_create(identity.identity) {
            sec_protocol_options_set_local_identity(security, localIdentity)
        }
        // The TV's certificate is self-signed: pairing is what proves it is the right TV, so any
        // certificate is accepted here and kept for the pairing secret.
        let peer = PeerCertificate()
        sec_protocol_options_set_verify_block(security, { _, trust, complete in
            let chain = SecTrustCopyCertificateChain(sec_trust_copy_ref(trust).takeRetainedValue()) as? [SecCertificate]
            peer.certificate = chain?.first
            complete(true)
        }, .main)
        self.peer = peer
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: tls))
    }

    func open(timeout: Duration = .seconds(10)) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            opening = continuation
            connection.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.stateChanged(state) }
            }
            connection.start(queue: .main)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                self.finishOpening(.failure(RemoteError.timedOut))
            }
        }
        receive()
    }

    func send(_ message: Data) {
        connection.send(content: ProtoWriter.framed(message), completion: .idempotent)
    }

    func next(timeout: Duration = .seconds(10)) async throws -> Data {
        if !queued.isEmpty { return queued.removeFirst() }
        if closed { throw RemoteError.connectionClosed }
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            waiter = (id, continuation)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if self.waiter?.id == id { self.resumeWaiter(.failure(RemoteError.timedOut)) }
            }
        }
    }

    func close() {
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] content, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let content { self.buffer.append(content) }
                do {
                    for frame in try ProtoMessage.takeFrames(from: &self.buffer) {
                        self.deliver(frame)
                    }
                } catch {
                    self.close()
                    return
                }
                if isComplete || error != nil {
                    self.close()
                } else {
                    self.receive()
                }
            }
        }
    }

    private func deliver(_ frame: Data) {
        if let onMessage {
            onMessage(frame)
        } else if waiter != nil {
            resumeWaiter(.success(frame))
        } else {
            queued.append(frame)
        }
    }

    private func flushQueued() {
        guard let onMessage else { return }
        while !queued.isEmpty { onMessage(queued.removeFirst()) }
    }

    private func resumeWaiter(_ result: Result<Data, Error>) {
        guard let waiter else { return }
        self.waiter = nil
        waiter.continuation.resume(with: result)
    }

    private func stateChanged(_ state: NWConnection.State) {
        switch state {
        case .ready:
            finishOpening(.success(()))
        case .waiting(let error), .failed(let error):
            finishOpening(.failure(error))
            close()
        case .cancelled:
            finishOpening(.failure(RemoteError.connectionClosed))
            didClose()
        default:
            break
        }
    }

    private func finishOpening(_ result: Result<Void, Error>) {
        guard let opening else { return }
        self.opening = nil
        opening.resume(with: result)
        if case .failure = result { close() }
    }

    private func didClose() {
        guard !closed else { return }
        closed = true
        resumeWaiter(.failure(RemoteError.connectionClosed))
        onClose?()
    }
}

private final class PeerCertificate: @unchecked Sendable {
    // Only touched on the main queue, which the verify block runs on.
    var certificate: SecCertificate?
}
