import Distributed
import Foundation

public struct TCPInvocationDecoder: DistributedTargetInvocationDecoder
{
    public typealias SerializationRequirement = any Codable

    private let envelope: TCPInvocationEnvelope
    private var argumentCursor = 0

    init(envelope: TCPInvocationEnvelope)
    {
        self.envelope = envelope
    }

    public mutating func decodeGenericSubstitutions() throws -> [Any.Type]
    {
        try envelope.genericSubs.map { mangled in
            guard let type = _typeByName(mangled) else {
                throw TCPError.decoding("cannot resolve type \(mangled)")
            }
            return type
        }
    }

    public mutating func decodeNextArgument<Argument: Codable>() throws -> Argument
    {
        guard argumentCursor < envelope.arguments.count else {
            throw TCPError.decoding("no argument at index \(argumentCursor)")
        }
        defer {
            argumentCursor += 1
        }
        return try JSONDecoder().decode(Argument.self, from: envelope.arguments[argumentCursor])
    }

    public mutating func decodeReturnType() throws -> Any.Type? { nil }
    public mutating func decodeErrorType() throws -> Any.Type? { nil }
}
