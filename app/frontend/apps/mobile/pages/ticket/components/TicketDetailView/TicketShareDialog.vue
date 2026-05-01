<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { onMounted, onUnmounted, ref, toRef } from 'vue'

import { NotificationTypes } from '#shared/components/CommonNotifications/types.ts'
import { useNotifications } from '#shared/components/CommonNotifications/useNotifications.ts'
import CommonUserAvatar from '#shared/components/CommonUserAvatar/CommonUserAvatar.vue'
import type { TicketById } from '#shared/entities/ticket/types.ts'
import { useTicketSharedAccess } from '#shared/entities/ticket-shared-access/composables/useTicketSharedAccess.ts'

import CommonButton from '#mobile/components/CommonButton/CommonButton.vue'
import CommonDialog from '#mobile/components/CommonDialog/CommonDialog.vue'
import CommonLoader from '#mobile/components/CommonLoader/CommonLoader.vue'
import { closeDialog } from '#mobile/composables/useDialog.ts'

export interface Props {
  name: string
  ticket: TicketById
}

interface SearchResult {
  id: string
  label: string
  email?: string
  firstname?: string
  lastname?: string
  image?: string
}

interface SearchApiResult {
  id: number
  type: string
}

interface UserAsset {
  firstname?: string
  lastname?: string
  email?: string
  image?: string
}

interface SearchApiResponse {
  result: SearchApiResult[]
  assets: {
    User?: Record<number, UserAsset>
  }
}

const props = defineProps<Props>()

const { notify } = useNotifications()

const { sharedUsers, isLoading, fetchSharedUsers, shareTicket, unshareTicket, canRemoveUser } =
  useTicketSharedAccess(toRef(props, 'ticket'))

const searchQuery = ref('')
const searchResults = ref<SearchResult[]>([])
const isSearching = ref(false)
const selectedUserId = ref<string | null>(null)
const selectedUserLabel = ref<string>('')
let searchDebounceTimer: ReturnType<typeof setTimeout> | null = null
let abortController: AbortController | null = null

onMounted(() => {
  fetchSharedUsers()
})

onUnmounted(() => {
  if (searchDebounceTimer) {
    clearTimeout(searchDebounceTimer)
  }
  if (abortController) {
    abortController.abort()
  }
})

const performSearch = async (query: string) => {
  isSearching.value = true

  // Cancel previous request if still pending
  if (abortController) {
    abortController.abort()
  }

  abortController = new AbortController()

  try {
    const ticketId = props.ticket?.internalId
    const response = await fetch(
      `/api/v1/ticket_shared_accesses/search?query=${encodeURIComponent(query)}&ticket_id=${ticketId}`,
      {
        headers: {
          'Content-Type': 'application/json',
        },
        credentials: 'same-origin',
        signal: abortController.signal,
      },
    )

    if (!response.ok) {
      throw new Error(__('Failed to search users'))
    }

    const data: SearchApiResponse = await response.json()
    const results = data.result || []
    const assets = data.assets || {}

    // Backend already filters out current user, ticket owner, and already shared users
    searchResults.value = results.map((item: SearchApiResult) => {
      const user = assets.User?.[item.id]
      if (user) {
        const fullname = [user.firstname, user.lastname].filter(Boolean).join(' ')
        return {
          id: String(item.id),
          label: fullname || user.email || `${__('User')} ${item.id}`,
          email: user.email,
          firstname: user.firstname,
          lastname: user.lastname,
          image: user.image,
        }
      }
      return {
        id: String(item.id),
        label: `${__('User')} ${item.id}`,
      }
    })
  } catch (error) {
    if (error instanceof Error && error.name !== 'AbortError') {
      notify({
        id: 'ticket-share-search-error',
        type: NotificationTypes.Error,
        message: __('Failed to search for customers. Please try again.'),
      })
    }
    searchResults.value = []
  } finally {
    isSearching.value = false
    abortController = null
  }
}

const searchUsers = () => {
  const query = searchQuery.value.trim()

  // Clear selected user when query changes
  selectedUserId.value = null
  selectedUserLabel.value = ''

  // Clear previous timer
  if (searchDebounceTimer) {
    clearTimeout(searchDebounceTimer)
  }

  if (query.length < 2) {
    searchResults.value = []
    isSearching.value = false
    return
  }

  // Set loading state immediately
  isSearching.value = true

  // Debounce the actual search by 300ms
  searchDebounceTimer = setTimeout(() => {
    performSearch(query)
  }, 300)
}

const handleShare = async () => {
  if (!selectedUserId.value) return

  const success = await shareTicket(selectedUserId.value)
  if (success) {
    searchQuery.value = ''
    searchResults.value = []
    selectedUserId.value = null
    selectedUserLabel.value = ''
  }
}

const handleUnshare = async (userId: string | number) => {
  await unshareTicket(String(userId))
}

const selectUser = (result: SearchResult) => {
  selectedUserId.value = result.id
  selectedUserLabel.value = result.label || result.id
  searchQuery.value = result.label || result.id
  searchResults.value = []
}

const cancelDialog = () => {
  closeDialog(props.name)
}
</script>

<template>
  <CommonDialog class="w-full" no-autofocus :name="name" :label="__('Share Ticket')">
    <template #before-label>
      <CommonButton transparent-background @click="cancelDialog">
        {{ $t('Cancel') }}
      </CommonButton>
    </template>
    <template #after-label>
      <CommonButton
        :disabled="!selectedUserId || isLoading"
        variant="primary"
        transparent-background
        @click="handleShare"
      >
        {{ $t('Share') }}
      </CommonButton>
    </template>

    <div class="flex flex-col gap-4 p-4">
      <!-- Description -->
      <p class="text-sm text-gray-100">
        {{ __('Share this ticket with another customer so they can read and comment on it.') }}
      </p>

      <!-- User Search -->
      <div class="flex flex-col gap-2">
        <FormKit
          id="mobile-customer-search"
          v-model="searchQuery"
          type="text"
          name="customer_search"
          :label="__('Customer')"
          :placeholder="__('Enter name or email')"
          :aria-label="__('Search for customer to share ticket with')"
          :aria-describedby="'mobile-search-description'"
          @input="searchUsers"
        />
        <span id="mobile-search-description" class="sr-only">
          {{ __('Type at least 2 characters to search for customers') }}
        </span>

        <!-- Search Results -->
        <div
          v-if="searchResults.length > 0"
          class="max-h-48 overflow-y-auto rounded border border-neutral-100 dark:border-gray-900"
          role="listbox"
          :aria-label="__('Search results')"
        >
          <button
            v-for="result in searchResults"
            :key="result.id"
            class="flex w-full items-center gap-3 px-3 py-3 text-left active:bg-blue-200 dark:active:bg-gray-700"
            role="option"
            :aria-selected="selectedUserId === result.id"
            :aria-label="`${__('Select')} ${result.label || result.id}`"
            @click="selectUser(result)"
          >
            <CommonUserAvatar
              :entity="{
                id: result.id,
                firstname: result.firstname,
                lastname: result.lastname,
                email: result.email,
                image: result.image,
              }"
              size="small"
            />
            <span class="text-sm">{{ result.label || result.id }}</span>
          </button>
        </div>

        <div
          v-if="isSearching"
          class="text-center text-sm text-gray-100"
          role="status"
          :aria-live="'polite'"
        >
          {{ __('Searching...') }}
        </div>
      </div>

      <!-- Divider -->
      <hr class="border-neutral-100 dark:border-gray-900" />

      <!-- Currently Shared With -->
      <div class="flex flex-col gap-3">
        <h3 class="text-sm font-semibold">
          {{ __('Currently shared with') }}
        </h3>

        <CommonLoader v-if="isLoading" :aria-label="__('Loading shared users')" />

        <div v-else-if="sharedUsers.length === 0" class="text-sm text-gray-100" role="status">
          {{ __('Not shared with anyone yet.') }}
        </div>

        <div
          v-else
          class="flex flex-col gap-2"
          role="list"
          :aria-label="__('Users with access to this ticket')"
        >
          <div
            v-for="sharedUser in sharedUsers"
            :key="sharedUser.id"
            class="flex items-center justify-between rounded border border-neutral-100 px-3 py-3 dark:border-gray-900"
            role="listitem"
          >
            <div class="flex items-center gap-3">
              <CommonUserAvatar
                :entity="{
                  id: String(sharedUser.user_id),
                  firstname: sharedUser.firstname,
                  lastname: sharedUser.lastname,
                  email: sharedUser.user_email,
                  image: sharedUser.image,
                }"
                size="small"
              />
              <span class="text-sm">{{
                sharedUser.user_name || `${__('User')} #${sharedUser.user_id}`
              }}</span>
            </div>

            <CommonButton
              v-if="canRemoveUser(sharedUser)"
              variant="danger"
              size="small"
              :disabled="isLoading"
              :aria-label="`${__('Remove access for user')} ${sharedUser.user_id}`"
              @click="handleUnshare(String(sharedUser.user_id))"
            >
              {{ __('Remove') }}
            </CommonButton>
          </div>
        </div>
      </div>
    </div>
  </CommonDialog>
</template>
