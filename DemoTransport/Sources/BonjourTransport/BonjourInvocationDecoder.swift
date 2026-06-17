import Distributed
import Foundation

public struct BonjourInvocationDecoder: DistributedTargetInvocationDecoder
{
    public typealias SerializationRequirement = any Codable

    private let envelope: BonjourInvocationEnvelope
    private var argumentCursor: Int = 0

    init(envelope: BonjourInvocationEnvelope)
    {
        self.envelope = envelope
    }

    public mutating func decodeGenericSubstitutions() throws -> [Any.Type]
    {
        // Resolve every recorded substitution so `executeDistributedTarget` can rebuild the generic
        // context of a generic actor's method (e.g. `DistributedActomaton`'s `Action`/`State`/…).
        try envelope.genericSubs.map { mangled in
            guard let type = _typeByName(mangled) else {
                throw BonjourActorSystemError.decodingFailure("cannot resolve type \(mangled)")
            }
            return type
        }
    }

    public mutating func decodeNextArgument<Argument: Codable>() throws -> Argument
    {
        guard argumentCursor < envelope.arguments.count else {
            throw BonjourActorSystemError.decodingFailure(
                "no argument at index \(argumentCursor)"
            )
        }
        let data = envelope.arguments[argumentCursor]
        argumentCursor += 1
        return try JSONDecoder().decode(Argument.self, from: data)
    }

    public mutating func decodeReturnType() throws -> Any.Type? { nil }
    public mutating func decodeErrorType() throws -> Any.Type? { nil }
}
