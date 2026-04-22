function athenaq -d "Run an Athena query and wait for completion"
    argparse 'r/region=' 'w/work-group=' 'p/profile=' -- $argv
    or return 1

    set -l region us-east-1
    set -l work_group primary

    if set -q _flag_region
        set region $_flag_region
    end

    if set -q _flag_work_group
        set work_group $_flag_work_group
    end

    if test (count $argv) -lt 2
        echo "Usage: athenaq [-r us-east-1] [-w primary] [-p profile] <database> <sql>" >&2
        return 1
    end

    set -l database $argv[1]
    set -e argv[1]
    set -l query (string join ' ' -- $argv)

    set -l aws_cmd aws
    if set -q _flag_profile
        set aws_cmd $aws_cmd --profile $_flag_profile
    end

    set -l qid ($aws_cmd athena start-query-execution \
        --region $region \
        --work-group $work_group \
        --query-execution-context Database=$database \
        --query-string "$query" \
        --query 'QueryExecutionId' --output text)

    if test $status -ne 0 -o -z "$qid"
        echo "athenaq: failed to start query" >&2
        return 1
    end

    echo "QueryExecutionId: $qid"

    while true
        set -l state ($aws_cmd athena get-query-execution \
            --region $region \
            --query-execution-id $qid \
            --query 'QueryExecution.Status.State' \
            --output text)

        echo "State: $state"

        if test "$state" = "SUCCEEDED"
            break
        else if test "$state" = "FAILED" -o "$state" = "CANCELLED"
            set -l reason ($aws_cmd athena get-query-execution \
                --region $region \
                --query-execution-id $qid \
                --query 'QueryExecution.Status.StateChangeReason' \
                --output text)
            echo "athenaq: $state - $reason" >&2
            return 1
        end

        sleep 2
    end

    $aws_cmd athena get-query-results --region $region --query-execution-id $qid
end
