import * as Types from '#shared/graphql/types.ts';

import gql from 'graphql-tag';
import { ErrorsFragmentDoc } from '../fragments/errors.api';
import * as VueApolloComposable from '@vue/apollo-composable';
import * as VueCompositionApi from 'vue';
export type ReactiveFunction<TParam> = () => TParam;

export const UserCurrentEmailNotificationsUpdateDocument = gql`
    mutation userCurrentEmailNotificationsUpdate($enabled: Boolean!) {
  userCurrentEmailNotificationsUpdate(enabled: $enabled) {
    success
    errors {
      ...errors
    }
  }
}
    ${ErrorsFragmentDoc}`;
export function useUserCurrentEmailNotificationsUpdateMutation(options: VueApolloComposable.UseMutationOptions<Types.UserCurrentEmailNotificationsUpdateMutation, Types.UserCurrentEmailNotificationsUpdateMutationVariables> | ReactiveFunction<VueApolloComposable.UseMutationOptions<Types.UserCurrentEmailNotificationsUpdateMutation, Types.UserCurrentEmailNotificationsUpdateMutationVariables>> = {}) {
  return VueApolloComposable.useMutation<Types.UserCurrentEmailNotificationsUpdateMutation, Types.UserCurrentEmailNotificationsUpdateMutationVariables>(UserCurrentEmailNotificationsUpdateDocument, options);
}
export type UserCurrentEmailNotificationsUpdateMutationCompositionFunctionResult = VueApolloComposable.UseMutationReturn<Types.UserCurrentEmailNotificationsUpdateMutation, Types.UserCurrentEmailNotificationsUpdateMutationVariables>;