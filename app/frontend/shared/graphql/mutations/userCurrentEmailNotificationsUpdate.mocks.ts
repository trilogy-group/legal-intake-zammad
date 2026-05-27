import * as Types from '#shared/graphql/types.ts';

import * as Mocks from '#tests/graphql/builders/mocks.ts'
import * as Operations from './userCurrentEmailNotificationsUpdate.api.ts'
import * as ErrorTypes from '#shared/types/error.ts'

export function mockUserCurrentEmailNotificationsUpdateMutation(defaults: Mocks.MockDefaultsValue<Types.UserCurrentEmailNotificationsUpdateMutation, Types.UserCurrentEmailNotificationsUpdateMutationVariables>) {
  return Mocks.mockGraphQLResult(Operations.UserCurrentEmailNotificationsUpdateDocument, defaults)
}

export function waitForUserCurrentEmailNotificationsUpdateMutationCalls() {
  return Mocks.waitForGraphQLMockCalls<Types.UserCurrentEmailNotificationsUpdateMutation>(Operations.UserCurrentEmailNotificationsUpdateDocument)
}

export function mockUserCurrentEmailNotificationsUpdateMutationError(message: string, extensions: {type: ErrorTypes.GraphQLErrorTypes }) {
  return Mocks.mockGraphQLResultWithError(Operations.UserCurrentEmailNotificationsUpdateDocument, message, extensions);
}
