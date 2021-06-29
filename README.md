# Keynote Template Deployment

Deploy a Keynote app template programmatically

## Background

Sometimes we want to programmatically set up a template for Keynote application.
There is a demand for distributing templates, especially in organizations.

## How to use

### With command line

The script will require three arguments.

```sh
./keynote-template-deployment.sh <Keynote template URL> <Display name of theme selector> <Type of specify the local users to be deployed>
```

### With Jamf Pro

This script supports Jamf Pro.

1. Upload this script to Jamf Pro.
1. Create new policy with the script.
1. Set arguments for the script.
    1. (Parameter 4) Keynote template URL
    1. (Parameter 5) Display name of theme selector
    1. (Parameter 6) Type of specify the local users to be deployed
        - `current`
        - `all`

## Parameters

### Keynote template URL

You can use files that are hosted remotely.

```sh
./keynote-template-deployment.sh "https://exmaple.com/sample.kth" "My Company Theme" "all"
```

You can also use the `file://` protocol to refer to local files. If you want to refer to `/tmp/sample.kth`, you should run the following command:

```sh
./keynote-template-deployment.sh "file:///tmp/sample.kth" "My Company Theme" "all"
```

### Display Name on theme selector

You can specify the name to be displayed in the Keynote appplication theme selector.

### Type of specify the local users to be deployed

You can select one of the following values.

- `all`
  - Applies to all local users of the device being run
  - root privilege is required
- `current`
  - Applies only to the currently running user

```sh
# If you want to deploy to all local users of the target device, specify the value `all` as the third argument.
./keynote-template-deployment.sh "https://example.com/sample.kth" "My Company Theme" "all"

# If you want to apply it only to the current user of the target device, specify the value `current` as the third argument.
./keynote-template-deployment.sh "https://example.com/sample.kth" "My Company Theme" "current"
```
