# Remote S3 + DynamoDB backend.
# Commented out so the code can run without a pre-existing state backend.
# Uncomment to activate. See docs-backend.md for bootstrap instructions.
#
# terraform {
#   backend "s3" {
#     bucket         = "ringr-tfstate-<unique-suffix>"
#     key            = "ringr-sip/prod/terraform.tfstate"
#     region         = "eu-west-1"
#     dynamodb_table = "ringr-tfstate-lock"
#     encrypt        = true
#   }
# }
