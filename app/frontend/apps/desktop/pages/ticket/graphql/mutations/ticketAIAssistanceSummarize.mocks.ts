import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './ticketAIAssistanceSummarize.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function mockTicketAiAssistanceSummarizeMutation(defaults: Mocks.MockDefaultsValue<Types.TicketAiAssistanceSummarizeMutation, Types.TicketAiAssistanceSummarizeMutationVariables>) {
  return Mocks.mockGraphQLResult(Operations.TicketAiAssistanceSummarizeDocument, defaults)
}

export function waitForTicketAiAssistanceSummarizeMutationCalls() {
  return Mocks.waitForGraphQLMockCalls<Types.TicketAiAssistanceSummarizeMutation>(Operations.TicketAiAssistanceSummarizeDocument)
}

export function mockTicketAiAssistanceSummarizeMutationError(message: string, extensions: {type: ErrorTypes.GraphQLErrorTypes }) {
  return Mocks.mockGraphQLResultWithError(Operations.TicketAiAssistanceSummarizeDocument, message, extensions);
}
