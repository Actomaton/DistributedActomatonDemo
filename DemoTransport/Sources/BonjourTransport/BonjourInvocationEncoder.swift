import Distributed
import Foundation

public struct BonjourInvocationEncoder: DistributedTargetInvocationEncoder
{
    public typealias SerializationRequirement = any Codable

    var genericSubs: [String] = []
    var arguments: [Data] = []

    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws
    {
        // `_mangledTypeName` (not `String(reflecting:)`) so the callee can resolve it via
        // `_typeByName` — required to reconstruct a *generic* actor's generic arguments.
        guard let mangled = _mangledTypeName(type) else {
            throw BonjourActorSystemError.notSupported("cannot mangle type \(type)")
        }
        genericSubs.append(mangled)
    }

    public mutating func recordArgument<Value: Codable>(
        _ argument: RemoteCallArgument<Value>
    ) throws
    {
        let data = try JSONEncoder().encode(argument.value)
        arguments.append(data)
    }

    public mutating func recordReturnType<R: Codable>(_ type: R.Type) throws {}
    public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {}
    public mutating func doneRecording() throws {}
}
