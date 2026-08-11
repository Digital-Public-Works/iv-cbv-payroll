# Retention is expressed as three separate knobs because they have very different
# reversibility, and collapsing them into one number hides that:
#
#   hot_days                  freely adjustable (storage class only)
#   expiration_days           freely adjustable (lifecycle rule)
#   object_lock_retention_days  IRREVERSIBLE upward-only in COMPLIANCE mode
#
# Object Lock retention on a version can be increased later but never decreased,
# so it is the one value worth being conservative about.

variable "hot_days" {
  description = "Days a report stays in S3 Standard before transitioning to the archive class. 90 matches AU-11's 'online' anchor."
  type        = number
  default     = 90

  validation {
    condition     = var.hot_days >= 90
    error_message = "hot_days must be at least 90 to satisfy the AU-11 online-retention anchor."
  }
}

variable "archive_storage_class" {
  description = "Storage class reports transition to after hot_days. GLACIER_IR keeps millisecond retrieval for assessors; GLACIER and DEEP_ARCHIVE are cheaper per GB but retrieval takes minutes to hours."
  type        = string
  default     = "GLACIER_IR"

  validation {
    condition     = contains(["GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], var.archive_storage_class)
    error_message = "archive_storage_class must be GLACIER_IR, GLACIER, or DEEP_ARCHIVE."
  }
}

# Placeholder pending the NARA/control-matrix citation. Safe to change at any time:
# a lifecycle rule can be edited freely, and it cannot delete a version whose Object
# Lock retention has not yet expired.
variable "expiration_days" {
  description = "Days after which a report is deleted. Must be >= object_lock_retention_days, or locked versions will simply survive the rule."
  type        = number
  default     = 1095 # 3 years

  validation {
    condition     = var.expiration_days >= 365
    error_message = "AU-11 windows are at least one year; a value below 365 days is almost certainly wrong."
  }
}

# No default, deliberately -- this is the irreversible one. In COMPLIANCE mode no
# principal including the account root can shorten it or delete a version before it
# expires. Set it to what you are certain of; it can be raised later.
variable "object_lock_retention_days" {
  description = "Object Lock default retention in days. IRREVERSIBLE: can be increased later but never decreased, and no principal can delete a version before it expires."
  type        = number

  validation {
    condition     = var.object_lock_retention_days >= 90
    error_message = "Object Lock retention must be at least the 90-day AU-11 online window."
  }
}

variable "object_lock_mode" {
  description = "Object Lock retention mode. COMPLIANCE cannot be bypassed by any principal including the account root; GOVERNANCE can be bypassed by principals holding s3:BypassGovernanceRetention."
  type        = string
  default     = "COMPLIANCE"

  validation {
    condition     = contains(["COMPLIANCE", "GOVERNANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be COMPLIANCE or GOVERNANCE."
  }
}
