import Distributed
import Foundation

public struct TCPInvocationEncoder: DistributedTargetInvocationEncoder
{
    public typealias SerializationRequirement = any Codable

    var genericSubs: [String] = []
    var arguments: [Data] = []

    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws
    {
        guard let mangled = _mangledTypeName(type) else {
            throw TCPError.unsupported("cannot mangle type \(type)")
        }
        genericSubs.append(mangled)
    }

    public mutating func recordArgument<Value: Codable>(_ argument: RemoteCallArgument<Value>) throws
    {
        arguments.append(try JSONEncoder().encode(argument.value))
    }

    public mutating func recordReturnType<R: Codable>(_ type: R.Type) throws {}
    public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {}
    public mutating func doneRecording() throws {}
}
