# Vendor patch fixtures

These are the unmodified files targeted by the telemetry-removal patch, taken
from the regenerated vendor tree for mongo-tools commit
`5e7290222cae7ebd5eade59bc19d6f25b637a1d3` using Go 1.27.1.

- github.com/Azure/azure-sdk-for-go/sdk/azcore v1.23.1 (MIT)
- github.com/AzureAD/microsoft-authentication-library-for-go v1.9.0 (MIT)
- github.com/aws/aws-sdk-go-v2 v1.47.0 (Apache-2.0)
- github.com/aws/aws-sdk-go v1.55.8 (Apache-2.0)

Their license files accompany the source. Tests apply the real patch to these
files and also mutate a fixture to verify that incompatible dependencies fail.
