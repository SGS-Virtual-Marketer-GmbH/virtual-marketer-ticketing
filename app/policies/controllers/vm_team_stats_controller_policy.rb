class Controllers::VMTeamStatsControllerPolicy < Controllers::ApplicationControllerPolicy
  # Zammad's own reporting permission, reused rather than invented: it already
  # exists, is assignable per role in the admin UI, and means precisely "may see
  # numbers beyond their own". Admins hold it out of the box; giving it to a
  # team lead is one role away and does not require making them an admin.
  default_permit!('report')
end
