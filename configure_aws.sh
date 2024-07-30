#! /bin/zsh

AWS_CONFIG_FILE=$HOME/.aws/config
SSO_URL=https://url.awsapps.com/start/#
SSO_SESSION_NAME=aws-sso
AWS_REGION=

# CA bundle seems to break initial setup
# unset AWS_CA_BUNDLE

# Create the AWS config file if it doesn't exist
if [ ! -d $HOME/.aws ]; then
  echo "Creating $AWS_CONFIG_FILE"
  mkdir $HOME/.aws
fi
if [ ! -f $AWS_CONFIG_FILE ]; then
  # configure SSO
  echo "adding sso-session configuration to $AWS_CONFIG_FILE"
  cat <<EOF > $AWS_CONFIG_FILE
[sso-session $SSO_SESSION_NAME]
sso_start_url = $SSO_URL 
sso_region = $AWS_REGION
sso_registration_scopes = sso:account:access
EOF
fi


# Get the Access token from the initial SSO login
CACHE_FILES_EXIST=$(find $HOME/.aws/sso/cache -name "*.json" 2> /dev/null | wc -l | xargs)

if [ $CACHE_FILES_EXIST -lt 2 ]; then
   echo "Cache files don't exist, attempting SSO login";
   # Retrieve initial access token and configure the sso-session
   aws sso login --sso-session bh-sso
fi

# Check the access token hasn't expired
expires=$(cat .aws/sso/cache/<cache_file>.json| jq -r ".expiresAt") # This needs fixing
expiry_time=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$expires" "+%s")
current_time=$(date "+%s")                                      
 
if (( expiry_time < current_time )); then 
    echo "Access token has expired, requesting new access token"
    aws sso login --sso-session bh-sso
fi

ACCESS_TOKEN=$(for file in ~/.aws/sso/cache/*; do if grep -q "startUrl" $file; then cat $file | jq -r ".accessToken"; fi; done)

# Retrieve the accounts
echo "Retrieving AWS account information"
next_run=0
next_token="0"


aws sso list-accounts --access-token $ACCESS_TOKEN --region eu-west-1  | jq -c '.accountList.[]' | while read i; do 
    account_id=$(jq -r '.accountId' <<< $i)
    account_name=$(jq -r '.accountName' <<< $i)
    echo "Checking if account $account_name exists in AWS configuration file"

    for role in $(aws sso list-account-roles --access-token $ACCESS_TOKEN --account-id $account_id --region eu-west-1 | jq -r ".roleList[].roleName"); do
    acct_name_no_space=$(echo $account_name | tr " " "-")
    profile_name="[profile $acct_name_no_space-$role]"
    if grep -q -F "$profile_name" $AWS_CONFIG_FILE; then
        echo "account $account_name already exists... ignoring"
        continue
    else
        echo "Account $account_name missing. Adding account"
        cat <<EOF >> $AWS_CONFIG_FILE

$profile_name
sso_session = $SSO_SESSION_NAME
sso_account_id = $account_id
sso_role_name = $role
EOF
    fi
    done

done
