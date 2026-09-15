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

# 3 years, matching expiration_days. Chosen deliberately rather than read off the
# control matrix, which has not yet been consulted -- see the AU-11 open item in
# docs/security/static-code-analysis.md. Under GOVERNANCE mode this is adjustable in
# either direction by a principal holding s3:BypassGovernanceRetention, so an
# incorrect value here is recoverable; under COMPLIANCE it would not be.
variable "object_lock_retention_days" {
  description = "Object Lock default retention in days. Under GOVERNANCE mode this can be raised or lowered by a principal with s3:BypassGovernanceRetention; under COMPLIANCE it could only ever be raised."
  type        = number
  default     = 1095 # 3 years

  validation {
    condition     = var.object_lock_retention_days >= 90
    error_message = "Object Lock retention must be at least the 90-day AU-11 online window."
  }
}

# GOVERNANCE, not COMPLIANCE. This is a deliberate trade-off:
#
#   + Recoverable. Brakeman JSON embeds source-code snippets, so a scan that captures
#     a hardcoded secret would otherwise be undeletable for the full retention window.
#   + Retention can be corrected in either direction before the matrix is confirmed.
#   - Weaker immutability claim. Any principal with s3:BypassGovernanceRetention can
#     delete a locked version, and the GitHub Actions role that writes these reports
#     currently has account-admin permissions (see PF-795), so the writer can remove
#     its own evidence. Scoping that role would restore the guarantee.
variable "object_lock_mode" {
  description = "Object Lock retention mode. COMPLIANCE cannot be bypassed by any principal including the account root; GOVERNANCE can be bypassed by principals holding s3:BypassGovernanceRetention."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["COMPLIANCE", "GOVERNANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be COMPLIANCE or GOVERNANCE."
  }
}
