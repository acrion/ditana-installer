set -e

playbook=$(config playbook)
echo "playbook: $playbook"

vars=$(config vars)
echo "playbook: $vars"

set +e
ansible-playbook -i localhost, $playbook -e "$vars"
exit_code=$?
set -e

echo "exit_code: $exit_code"