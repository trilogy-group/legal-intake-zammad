<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, ref } from 'vue'
import { toRef } from 'vue'

import {
  NotificationTypes,
  useNotifications,
} from '#shared/components/CommonNotifications/index.ts'
import { MutationHandler } from '#shared/server/apollo/handler/index.ts'
import { useSessionStore } from '#shared/stores/session.ts'

import LayoutContent from '#desktop/components/layout/LayoutContent.vue'
import { useBreadcrumb } from '#desktop/pages/personal-setting/composables/useBreadcrumb.ts'
import { useUserCurrentEmailNotificationsUpdateMutation } from '#shared/graphql/mutations/userCurrentEmailNotificationsUpdate.api.ts'

const { breadcrumbItems } = useBreadcrumb(__('Email Notifications'))

const session = useSessionStore()
const user = toRef(session, 'user')

const { notify } = useNotifications()

const saving = ref(false)

const emailNotificationsEnabled = computed({
  get: () => {
    const pref = user.value?.preferences?.email_notifications_enabled
    // Default to true when no preference is stored
    return pref === undefined || pref === null ? true : Boolean(pref)
  },
  set: async (enabled: boolean) => {
    saving.value = true

    const mutation = new MutationHandler(
      useUserCurrentEmailNotificationsUpdateMutation({ variables: { enabled } }),
      {
        errorNotificationMessage: __('Email notification preference could not be saved.'),
      },
    )

    const result = await mutation.send({ enabled }).finally(() => {
      saving.value = false
    })

    if (!result?.userCurrentEmailNotificationsUpdate?.success) return

    // Update the local session preferences so the toggle reflects immediately
    if (user.value?.preferences) {
      user.value.preferences.email_notifications_enabled = enabled
    }

    notify({
      id: 'email-notifications-update',
      message: __('Email notification preference has been saved.'),
      type: NotificationTypes.Success,
    })
  },
})
</script>

<template>
  <LayoutContent :breadcrumb-items="breadcrumbItems" width="narrow" provide-default>
    <div class="mb-4 space-y-3">
      <p class="text-sm text-stone-200 dark:text-neutral-500">
        {{
          $t(
            'Control whether you receive email notifications for tickets shared with you. This only applies to tickets you did not create — you will always receive notifications for tickets you opened.',
          )
        }}
      </p>

      <FormKit
        v-model="emailNotificationsEnabled"
        type="toggle"
        name="email_notifications_enabled"
        :label="$t('Receive email notifications for tickets shared with me')"
        :disabled="saving"
        :variants="{ true: __('Enabled'), false: __('Disabled') }"
      />
    </div>
  </LayoutContent>
</template>
