enum BonjourFrame: Codable, Sendable
{
    case hello(BonjourHelloPayload)
    case invocation(BonjourInvocationEnvelope)
    case reply(BonjourReplyEnvelope)
}
