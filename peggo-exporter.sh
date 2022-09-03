#!/bin/bash

MY_ORCH="umee1f8rccu6hty2y6ggdux2fqc9eg535f7dvqp0n7w"	# our orchestrator address
END_POINT="127.0.0.1:1317"				                    # peggo endpoint
HEALTH_CHECK="127.0.0.1:26657/status"		              # sync condition check

separate_my_validator="true"				  # add additional metrics section for "$MY_ORCH" ( useful to monitor only particular validator by setting all the rest options to 'false' )

print_full_cluster_metrics="true"			# if need full cluster metrics
print_nonce_statistic="true"				  # nonce statistic ( top tip, bottom non zero, total collected )
print_bogus_counter="true"				    # how many validators have nonce 0 ( nonsense placeholders )

# if all above set to 'false' only execution time will popup, no useful metrics will be printed.
# if '$separate_my_validator' set to 'true', this validator 'will not be excluded' from full cluster metrics. Full cluster metrics is complete and contain all 'BONDED' validators.

# a simple text file, point anywhere with write permission. 'Set carefuly, this file will be truncated each script execution'
tmp_db=${HOME}/peggo-check/metrics.db

# we can serve this metrics with nginx for example ( /var/www/peggo_metrics/index.html )
serve_metrics_here=${HOME}/peggo-check/nginx.page

# ----------------------------------------------------

numba='^[0-9]+$'

truncate -s 0 "${tmp_db}"

# construct prometheus metrics in appropriate format.
function prometheus_constructor() {

  # 1=$valoper 2=$orchestrator_address 3=$etherium_address 4=$event_nonce 5=tag
  echo "$5{valoper=\"$1\",orch_address=\"$2\",eth_address=\"$3\"} $4"

}

function main() {

  bogus_state=0

  # print header if $print_full_cluster_metrics set to true
  if [[ "$print_full_cluster_metrics" =~ true ]]; then

	# prometheus metrics header
	echo "# HELP pego_validator_nonce_total Peggo nonce for each bonded validator"
	echo "# TYPE pego_validator_nonce_total counter"

  fi

  # collect all bonded operators in to array
  IFS=$'\n' activeValidators_set=($(curl -s http://"$END_POINT"/cosmos/staking/v1beta1/validators?status=BOND_STATUS_BONDED | jq -r '.validators | .[].operator_address'))

  for valoper in "${activeValidators_set[@]}"; do

	# get orchestrator data ( eth adddress and orchestrator address )
	orchestrator_data=$(curl -s http://"${END_POINT}"/gravity/v1beta/query_delegate_keys_by_validator?validator_address="$valoper")

	orchestrator_address="$(jq -r .orchestrator_address <<< $orchestrator_data)"

	# validate orch address ( can be better )
	if ! [[ $orchestrator_address == umee1* ]]; then orchestrator_address="bollocks"; fi

	etherium_address="$(jq -r .eth_address <<< $orchestrator_data)"

	# validate eth address ( can be better )
	if ! [[ $etherium_address == 0x* ]]; then etherium_address="bollocks"; fi

	# get nonce by using orch address
	event_nonce=$(curl -s http://"${END_POINT}"/gravity/v1beta/oracle/eventnonce/"$orchestrator_address" | jq -r .event_nonce)

	# validate if nonce is a number
	if ! [[ "$event_nonce" =~ $numba ]]; then event_nonce="0"; bogus_state=$((bogus_state + 1)); fi

	if [[ "$orchestrator_address" =~  $MY_ORCH ]] && [[ "$separate_my_validator" =~ true  ]]; then

		my_orchestrator_address="$orchestrator_address"
		my_etherium_address="$etherium_address"
		my_event_nonce="$event_nonce"
		my_valoper="$valoper"

	fi

	# print each validator data if $print_full_cluster_metrics set to true
	if [[ "$print_full_cluster_metrics" =~ true ]]; then
		prometheus_constructor "$valoper" "$orchestrator_address" "$etherium_address" "$event_nonce" "pego_validator_nonce_total"
	fi

	nonce_arr+=("$event_nonce")

  done

} >> "$tmp_db" # collect data from function

# get top nonce of the cluster as well as the lowest non zero ( not sure yet what the lowest one for, but theoretically should be equil tip, otherwise technically cluster health sucks.
function get_tip() {

  collected_nonce_amount="${#nonce_arr[@]}"

  cluster_tip=0

  # get tip of the cluster
  for nonce in "${nonce_arr[@]}"; do

    if [[ "$nonce" -gt "$cluster_tip" ]]; then
	      cluster_tip="$nonce" # increment till we get to the top, as we eventually will
    fi

  done

  bottom_nonce="$cluster_tip"

  # get bottom bogus ( non zero ) nonce. Zero ( not set ) orchestrator will be separated to different braket ( aka bad ).
  for nonce in "${nonce_arr[@]}"; do

    if [[ "$nonce" -lt "$bottom_nonce" ]] && [[ "$nonce" -ne 0 ]]; then
	      bottom_nonce="$nonce" # decrease from top till we get to the bottom
    fi

  done

if [[ "$print_nonce_statistic" =~ true  ]]; then

  echo "# HELP peggo_collected_nonce Amount of nonce in nonce array collected from last exporter execution ( expected 100 )."
  echo "# TYPE peggo_collected_nonce gauge"
  echo "peggo_collected_nonce ${#nonce_arr[@]}"

  echo "# HELP peggo_cluster_tip_total Top cluster nonce"
  echo "# TYPE peggo_cluster_tip_total counter"
  echo "peggo_cluster_tip_total $cluster_tip"

  echo "# HELP peggo_cluster_bottom Bottop non zero cluster  nonce"
  echo "# TYPE peggo_cluster_bottom gauge"
  echo "peggo_cluster_bottom $bottom_nonce"

fi

} >> "$tmp_db" # collect data from function

# individual validator stats if set to true
function my_validator_stats() {

  calculated_diff=$((cluster_tip - my_event_nonce))

  echo "# HELP peggo_my_stats_total Selected validator separated to additional section here."
  echo "# TYPE peggo_my_stats_total counter"

  prometheus_constructor "$my_valoper" "$my_orchestrator_address" "$my_etherium_address" "$my_event_nonce" "peggo_my_stats_total"

  echo "# HELP peggo_my_calculated_diff Selected validator difference from top of the cluster ( expected 0, no difference) use for alerts of whatever."
  echo "# TYPE peggo_my_calculated_diff gauge"
  echo "peggo_my_calculated_diff $calculated_diff"

} >> "$tmp_db" # collect data from function

function print_bogus_counter() {

  echo "# HELP peggo_bogus_validators Zero nonce instances ( expect 0)."
  echo "# TYPE  peggo_bogus_validators gauge"
  echo "peggo_bogus_validators $bogus_state"

} >> "$tmp_db" # collect data from function

function execution_time() {

  duration=$(echo "$(date +%s.%N) - $time_start" | bc)
  execution_time=$(printf "%.2f seconds" "$duration")

  echo "# HELP peggo_exporter_execution_duration Exporter last execution time."
  echo "# TYPE peggo_exporter_execution_duration gauge"
  echo "peggo_exporter_execution_duration $execution_time"

} >> "$tmp_db" # collect data from function

# check if our RPC is in sync
function check_rpc_sync() {

  is_rpc_in_sync=$(curl -s "${HEALTH_CHECK}" | jq .result.sync_info.catching_up)

  if ! [[ "$is_rpc_in_sync" =~ false ]]; then

    sed -i 's/peggo_exporter_rpc_check 0/peggo_exporter_rpc_check 1/g' "${serve_metrics_here}"

    exit 1

  fi

}

# we assume where is no errors, all values are 0. This will be overwritten if issues found.
function write_dummy_checks() {

  echo "# HELP peggo_exporter_rpc_sync_check Approximate health of exporter RPC source"
  echo "# TYPE peggo_exporter_rpc_sync_check gauge"
  echo "peggo_exporter_rpc_sync_check 0"

  echo "# HELP approximate_health_state Approximate health of exporter engine"
  echo "# TYPE approximate_health_state gauge"
  echo "approximate_health_state 0"

} >> "$tmp_db" # collect data from function

# check if enough data collected
# if database contain less then X amount of umee1 addresses treat this as failure. ( the ideal solution will be infinity regex check line.
# Life is to short for promtool
function check_db_sanity() {

  umee1_found=$(grep -o umee1 "$tmp_db" | wc -l)

  if [[ "$umee1_found" -lt 65 ]]; then

    # change failure state to 1
    sed -i 's/approximate_health_state 0/approximate_health_state 1/g' "${serve_metrics_here}"

    exit 1

  fi

}

# assume exporter never fail. ( the ideal solution will be infinity regex check line.
sed -i 's/approximate_health_state 1/approximate_health_state 0/g' "$tmp_db"
# assume RPC always in sync
sed -i 's/peggo_exporter_rpc_check 1/peggo_exporter_rpc_check 0/g' "$tmp_db"

time_start=$(date +%s.%N) # record start position in time

check_rpc_sync # checking if RPC is in sync

write_dummy_checks # initial placeholders

declare -a nonce_arr=() # will hold all current nonces from all validators

main	# main function

get_tip	# get top cluster nonce and non zero bottom ( not sure what this bottom for, maybe cluster health calculation will be added later, as theoretically we want absolute performance).

# print selected validator metrics separately 'if $separate_my_validator set to true', otherwise not. ( validator still included in main function, is not excluded )
if [[ "$separate_my_validator" =~ true  ]]; then my_validator_stats; fi

# print how many validators have nonce equil zero
if [[ "$print_bogus_counter" =~ true  ]]; then print_bogus_counter; fi

execution_time # print how long it takes to process all tasks in this script from start to finish

check_db_sanity

cat "${tmp_db}" > "${serve_metrics_here}" # update page

cat "${serve_metrics_here}" # debug
