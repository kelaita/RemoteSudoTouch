import Foundation
import LocalAuthentication
import Network

struct TouchIDRequest: Decodable {
  let request_id: String
  let timestamp: Int
  let hostname: String
  let user: String
  let service: String
  let tty: String
  let rhost: String
  let type: String
}

struct TouchIDResponse: Encodable {
  let request_id: String
  let approved: Bool
  let reason: String?
}

final class TouchIDAgentServer {
  private let listener: NWListener
  private let queue = DispatchQueue(label: "RemoteSudoTouchAgent.listener")

  init(port: UInt16) throws {
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!)
    listener = try NWListener(using: parameters)
  }

  func start() {
    listener.stateUpdateHandler = { state in
      fputs("listener state: \(state)\n", stderr)
    }

    listener.newConnectionHandler = { [weak self] connection in
      self?.handle(connection: connection)
    }

    listener.start(queue: queue)
    dispatchMain()
  }

  private func handle(connection: NWConnection) {
    connection.start(queue: queue)
    receive(on: connection, buffer: Data())
  }

  private func receive(on connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
      guard let self else {
        connection.cancel()
        return
      }

      if let error {
        fputs("connection error: \(error)\n", stderr)
        connection.cancel()
        return
      }

      var combined = buffer
      if let data {
        combined.append(data)
      }

      if let newlineIndex = combined.firstIndex(of: 0x0A) {
        let payload = combined.prefix(upTo: newlineIndex)
        self.respond(to: connection, requestData: Data(payload))
        return
      }

      if isComplete {
        self.respond(to: connection, requestData: combined)
        return
      }

      self.receive(on: connection, buffer: combined)
    }
  }

  private func respond(to connection: NWConnection, requestData: Data) {
    let response: TouchIDResponse

    do {
      let request = try JSONDecoder().decode(TouchIDRequest.self, from: requestData)
      response = authorize(request: request)
    } catch {
      response = TouchIDResponse(request_id: "", approved: false, reason: "bad_request")
    }

    do {
      let payload = try JSONEncoder().encode(response) + Data([0x0A])
      connection.send(content: payload, completion: .contentProcessed { _ in
        connection.cancel()
      })
    } catch {
      connection.cancel()
    }
  }

  private func authorize(request: TouchIDRequest) -> TouchIDResponse {
    if request.type == "health_check" {
      return TouchIDResponse(request_id: request.request_id, approved: true, reason: nil)
    }

    let semaphore = DispatchSemaphore(value: 0)
    let context = LAContext()
    context.localizedCancelTitle = "Deny"

    var biometricError: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError) else {
      return TouchIDResponse(
        request_id: request.request_id,
        approved: false,
        reason: "biometrics_unavailable"
      )
    }

    let prompt = "Approve sudo for \(request.user) on \(request.hostname)"
    var approved = false
    var denialReason: String? = nil

    context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: prompt) { success, error in
      approved = success
      if !success {
        denialReason = (error as NSError?)?.localizedDescription ?? "denied"
      }
      semaphore.signal()
    }

    if semaphore.wait(timeout: .now() + 30) == .timedOut {
      return TouchIDResponse(request_id: request.request_id, approved: false, reason: "timeout")
    }

    return TouchIDResponse(
      request_id: request.request_id,
      approved: approved,
      reason: approved ? nil : (denialReason ?? "denied")
    )
  }
}

private func parsePort() -> UInt16 {
  let args = CommandLine.arguments

  if let index = args.firstIndex(of: "--port"), args.indices.contains(index + 1), let port = UInt16(args[index + 1]) {
    return port
  }

  return 8765
}

do {
  let server = try TouchIDAgentServer(port: parsePort())
  server.start()
} catch {
  fputs("Failed to start RemoteSudoTouchAgent: \(error)\n", stderr)
  exit(1)
}
