#!env bash
TEST_DIR="test"

function not2xxHTTPCode() {
    http_code="$1"
    if (( http_code < 200 || http_code >= 300 )); then
        return 0
    fi
    return 1
}

function partialOutput() {
  local DATA_OUT="$1"
  local nHEAD=5
  local nTAIL=3
  if [[ $(wc -l <"${DATA_OUT}") -le $((nHEAD+nTAIL)) ]]; then
    cat ${DATA_OUT}
  else
    head -n ${nHEAD} "${DATA_OUT}"
    echo "..."
    tail -n ${nTAIL} "${DATA_OUT}"
  fi
  echo
}

function curlTest() {
  # $1: testXX data var name
  local -n data="$1"
  local -a args=()
  if  [[ -n "${data[args]}" ]]; then
    local -n dataArgs="${data[args]}"
    args=("${dataArgs[@]}")
  fi
  args+=("${data[url]}")
  rc=0
  DATA_OUT="${TEST_DIR}/test.out"
  HEADER_OUT="${TEST_DIR}/headers.txt"
  resp="$(curl -D ${HEADER_OUT} -w '\n%{http_code}' --output ${DATA_OUT} "${args[@]}")"
  retVal=$?
  STATUS_CODE="$(tail -n1 <<< "${resp}")"  # get the last line
  HEADERS="$(cat ${HEADER_OUT})"
  CMD=""
  for i in "${args[@]}"; do
    if [[ ${i} =~ [\"] ]]; then
      i=\'${i}\'
    elif [[ ${i} =~ [[:space:]\'] ]]; then
      i=\"${i}\"
    fi
    if [[ -z "${CMD}" ]]; then
      CMD="${i}"
    else
      CMD="${CMD} ${i}"
    fi
  done
  echo "Executing curl ${CMD}..."
  echo "-> Response headers:"
  echo "${HEADERS}"
  echo "-> End of headers."
  echo "-> curl output (cURL status: ${retVal}, HTTP response code: ${STATUS_CODE}):"
  if [ ${retVal} -ne 0 ]; then
    cat ${DATA_OUT}; echo
    echo "-> End of output."
    echo "ERROR: Failed to execute cURL: Bad cURL status: ${retVal}!"
    rc=1
    rm -f ${DATA_OUT} ${HEADER_OUT}
    return ${rc}
  fi
  case "${TEST_TYPE}" in
    "regular" )
      partialOutput ${DATA_OUT}
      echo "-> End of output."
      if not2xxHTTPCode "${STATUS_CODE}"; then
        echo "ERROR: Failed to execute cURL: Bad HTTP response ${STATUS_CODE}!"
        rc=1
      fi
      ;;
    "err" )
      partialOutput ${DATA_OUT}
      echo "-> End of output."
      if not2xxHTTPCode "${STATUS_CODE}"; then
        echo "--> Got the expected error code!"
      else
        echo "ERROR: Expected an error, but got none (${STATUS_CODE})!"
        rc=2
      fi
      ;;
    * )
      echo "ERROR: Unknown test type: ${TEST_TYPE}!"
      rc=3
      ;;
  esac
}

function testWith() {
  # $1: testXX data var name
  # $2: stats var name
  # $3: list var name
  local -n data="$1"
  local -n theStat="$2"
  local -n theList="$3"
  echo "===== $1 ====="
  echo "*** Test ${data[name]} with test type '${data[type]}'..."
  if TEST_TYPE="${data[type]}" curlTest "$1"; then
    echo "**** PASS: ${data[name]}"
    (( theStat['nPASS']++ ))
    theList+=("PASS $1 (type '${data[type]}'): ${data[name]}")
  else
    echo "**** FAIL: ${data[name]}"
    (( theStat['nFAIL']++ )) 
    theList+=("FAIL $1 (type '${data[type]}'): ${data[name]}")
  fi
  echo "Done testing ${data[name]} with test type '${data[type]}'."
  echo
}

# set up
if [[ ! -d "${TEST_DIR}" ]]; then
    mkdir "${TEST_DIR}"
fi

declare -A testCurl01=(
  ['name']="test_GET"
  ['type']="regular"
  ['url']="https://www.apple.com"
  ['args']=''
)
declare -a headArgs=("-I")
declare -A testCurl02=(
  ['name']="test_HEAD"
  ['type']="regular"
  ['url']="https://www.apple.com"
  ['args']='headArgs'
)

declare -a postArgs=("-X" "POST" "-H" "Content-Type: application/json" "-d" '{"data": {"key":"value"}' )
declare -A testCurl03=(
  ['name']="test_POST"
  ['type']="err"
  ['url']="https://www.apple.com"
  ['args']='postArgs'
)

declare -A stats=(
  ['nPASS']=0
  ['nFAIL']=0
)

declare -a testList=()

for test in ${!testCurl@}; do
  testWith "${test}" stats testList
done

#clean up
rm -f ${TEST_DIR}/*

echo
echo "*** List of tests ***"
printf '%s\n' "${testList[@]}"
echo "*** Summary ***"
TOTAL=$((stats[nPASS] + stats[nFAIL]))
echo "Total ${stats[nPASS]} passed and ${stats[nFAIL]} failed out of ${TOTAL} tests performed."
echo "Done."
