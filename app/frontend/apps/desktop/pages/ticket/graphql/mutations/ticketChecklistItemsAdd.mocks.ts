import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './ticketChecklistItemsAdd.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function mockTicketChecklistItemsAddMutation(defaults: Mocks.MockDefaultsValue<Types.TicketChecklistItemsAddMutation, Types.TicketChecklistItemsAddMutationVariables>) {
  return Mocks.mockGraphQLResult(Operations.TicketChecklistItemsAddDocument, defaults)
}

export function waitForTicketChecklistItemsAddMutationCalls() {
  return Mocks.waitForGraphQLMockCalls<Types.TicketChecklistItemsAddMutation>(Operations.TicketChecklistItemsAddDocument)
}

export function mockTicketChecklistItemsAddMutationError(message: string, extensions: {type: ErrorTypes.GraphQLErrorTypes }) {
  return Mocks.mockGraphQLResultWithError(Operations.TicketChecklistItemsAddDocument, message, extensions);
}
