# Terraform Remote Backend — Decision and Configuration

## The problem

`terraform.tfstate` is the "map" between your code and the real deployed infrastructure.
It has two properties that make it dangerous to manage carelessly:

1. **It contains sensitive data in plain text** (endpoints, sometimes generated secrets,
   ARNs). That is why it must NEVER go in Git (see `.gitignore`).
2. **It is the shared source of truth.** If two people (or two pipelines) run `apply`
   simultaneously against the same state, they corrupt it.

## The decision: S3 + DynamoDB backend

- **S3** stores the state file with versioning and encryption at rest.
- **DynamoDB** provides *state locking*: while someone is applying, the state is locked
  and nobody else can write to it. This prevents corruption from concurrent access.

This is the standard combination for Terraform on AWS before adding tools such as
Terraform Cloud or Atlantis.

## Environment isolation (key to this architecture)

Each environment has a **separate state**, in line with the Operations requirement
("deploy both environments independently"). This is achieved with a distinct `key` per
environment inside the same bucket (or separate buckets/accounts):

- prod    → key = "ringr-sip/prod/terraform.tfstate"
- nonprod → key = "ringr-sip/nonprod/terraform.tfstate"

This means an `apply` in nonprod cannot touch the prod state.

## Configuration (goes in each environments/<env>/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "ringr-tfstate-<unique-suffix>"
    key            = "ringr-sip/prod/terraform.tfstate"  # change per environment
    region         = "eu-west-1"
    dynamodb_table = "ringr-tfstate-lock"
    encrypt        = true
  }
}
```

## Note for testing

The S3 bucket and DynamoDB table must exist BEFORE the first `init` (the
chicken-and-egg problem: the backend cannot create itself). In a real project they are
created with a small separate bootstrap Terraform configuration, or manually once.

To keep the code runnable without standing up this prior infrastructure, the `backend.tf`
files in each environment are delivered **commented out**, so Terraform defaults to a
local backend. Uncommenting them activates the remote backend. This keeps the code
executable end-to-end while documenting the correct practice.
