// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import type { PersonalSettingPlugin } from './types.ts'

export default <PersonalSettingPlugin>{
  label: __('Email Notifications'),
  category: {
    label: __('Tickets'),
    id: 'category-tickets',
    order: 3000,
  },
  route: {
    path: 'email-notifications',
    alias: '/profile/email-notifications',
    name: 'PersonalSettingEmailNotifications',
    component: () => import('../../PersonalSettingEmailNotifications.vue'),
    level: 1,
    meta: {
      title: __('Email Notifications'),
      requiresAuth: true,
      requiredPermission: 'user_preferences.email_notifications+ticket.customer',
    },
  },
  order: 1100,
  keywords: __('email,notifications,unsubscribe,opt-out'),
}
