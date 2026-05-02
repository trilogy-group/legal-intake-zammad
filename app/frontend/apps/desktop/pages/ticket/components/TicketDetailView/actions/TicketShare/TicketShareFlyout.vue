<!-- Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { onMounted, onUnmounted, ref, toRef } from 'vue'

import { NotificationTypes } from '#shared/components/CommonNotifications/types.ts'
import { useNotifications } from '#shared/components/CommonNotifications/useNotifications.ts'
import CommonUserAvatar from '#shared/components/CommonUserAvatar/CommonUserAvatar.vue'
import type { TicketById } from '#shared/entities/ticket/types.ts'
import { useTicketSharedAccess } from '#shared/entities/ticket-shared-access/composables/useTicketSharedAccess.ts'

import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import CommonFlyout from '#desktop/components/CommonFlyout/CommonFlyout.vue'
import CommonLoader from '#desktop/components/CommonLoader/CommonLoader.vue'

interface Props {
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

const ticketShareFlyoutName = 'ticket-share'

const { sharedUsers, isLoading, fetchSharedUsers, shareTicket, unshareTicket, canRemoveUser } =
  useTicketSharedAccess(toRef(props, 'ticket'))

const searchQuery = ref('')
const searchResults = ref<SearchResult[]>([])
const isSearching = ref(false)
const selectedUserId = ref<string | null>(null)
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

  const currentController = new AbortController()
  abortController = currentController

  try {
    const ticketId = props.ticket?.internalId
    const response = await fetch(
      `/api/v1/ticket_shared_accesses/search?query=${encodeURIComponent(query)}&ticket_id=${ticketId}`,
      {
        headers: {
          'Content-Type': 'application/json',
        },
        credentials: 'same-origin',
        signal: currentController.signal,
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
    // Only clear if this controller is still the active one
    if (abortController === currentController) {
      abortController = null
    }
  }
}

const searchUsers = () => {
  const query = searchQuery.value.trim()

  // Clear selected user when query changes
  selectedUserId.value = null

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
  }
}

const handleUnshare = async (userId: string | number) => {
  await unshareTicket(String(userId))
}

const selectUser = (result: SearchResult) => {
  selectedUserId.value = result.id
  searchQuery.value = result.label || result.id
  searchResults.value = []
}
</script>

<template>
  <CommonFlyout
    header-icon="user"
    :name="ticketShareFlyoutName"
    :header-title="__('Share Ticket')"
    no-close-on-action
  >
    <div class="flex flex-col gap-4 p-4">
      <!-- Description -->
      <p class="text-sm text-gray-100">
        {{ __('Share this ticket with another customer so they can read and comment on it.') }}
      </p>

      <!-- User Search -->
      <div class="flex flex-col gap-2">
        <div class="flex gap-2">
          <!-- eslint-disable-next-line vuejs-accessibility/label-has-for -->
          <label class="flex flex-1 flex-col gap-1">
            <span class="text-sm font-semibold">{{ __('Customer') }}</span>
            <input
              id="customer-search"
              v-model="searchQuery"
              type="text"
              name="customer_search"
              class="focus:border-blue w-full rounded border border-gray-300 px-3 py-2 text-sm focus:outline-none"
              :placeholder="__('Enter name or email')"
              :aria-label="__('Search for customer to share ticket with')"
              aria-describedby="search-description"
              @input="searchUsers"
            />
          </label>
          <CommonButton
            variant="submit"
            :disabled="!selectedUserId || isLoading"
            :aria-label="__('Share ticket with selected customer')"
            class="self-end"
            @click="handleShare"
          >
            {{ __('Share') }}
          </CommonButton>
        </div>
        <span id="search-description" class="sr-only">
          {{ __('Type at least 2 characters to search for customers') }}
        </span>

        <!-- Search Results -->
        <div
          v-if="searchResults.length > 0"
          class="max-h-48 overflow-y-auto rounded border border-gray-300"
          role="listbox"
          :aria-label="__('Search results')"
        >
          <button
            v-for="result in searchResults"
            :key="result.id"
            class="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-blue-100"
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
      <hr class="border-gray-300" />

      <!-- Currently Shared With -->
      <div class="flex flex-col gap-2">
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
            class="flex items-center justify-between rounded border border-gray-300 px-3 py-2"
            role="listitem"
          >
            <div class="flex items-center gap-2">
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
                sharedUser.user_name || `User #${sharedUser.user_id}`
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
  </CommonFlyout>
</template>
