set -e

export SP6_FORMAT_COLOR=1
export SP6_LOG_NO_TIMESTAMPS=1

task=$(config task)
echo "task: $task"

vars=$(config vars)
echo "vars: $vars"

set +e
s6 --task-run $task@$vars
exit_code=$?
set -e

echo "exit_code: $exit_code"