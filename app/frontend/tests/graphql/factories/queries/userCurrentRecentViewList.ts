// Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

import type { UserCurrentRecentViewListQuery } from '#shared/graphql/types.ts'

export default (): UserCurrentRecentViewListQuery => {
  return {
    userCurrentRecentViewList: [],
  }
}
