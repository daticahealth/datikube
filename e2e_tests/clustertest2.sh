#!/bin/bash
SCRIPT_NAME=$(echo $0 | sed s/".*\/"//)
ASSERT_SCRIPT=$(echo $0 | sed s/"$SCRIPT_NAME"/"assert.sh"/)
source "$ASSERT_SCRIPT"

#---------------------------- Constants and Variables--------------------------

readonly BASE_PATH=$(dirname $0)
readonly NAME=test-data
readonly ORIG_NAME=example-crud
readonly DEFAULT_NAMESPACE=default

readonly ROLE=$NAME
readonly ROLEBINDING=$NAME
readonly SERVICEACCOUNT=$NAME

readonly DEPLOYMENT=mysql-${NAME}
readonly SERVICE=mysql-${NAME}
readonly STORAGECLASS=${NAME}-demo-storage-class
readonly PVC=mysql-${NAME}-claim

readonly INGRESS=ingress-${NAME}
readonly SECRET=ingress-tls-${NAME}

readonly API_DEPLOYMENT=$NAME
readonly API_SERVICE=$NAME

readonly SSL_KEY_FILE=$BASE_PATH/certs/key.pem
readonly SSL_CRT_FILE=$BASE_PATH/certs/cert.pem
readonly OPENSSL_CONFIG_FILE=$BASE_PATH/certs/openssl.conf

namespace=$DEFAULT_NAMESPACE
context=''
admincrt=''
adminkey=''
sslkey=''
sslcrt=''
loadbalancer=''
clusteradmin=''

#---------------------------------Helpers-------------------------------------
kube() {
  local YAML=$1
  local INGR=$2
  cat $YAML | sed s,"example-crud","$NAME",g | sed s,"{{ hostname }}",${INGR},g | kubectl --context=${context} apply -f -
}

kube-wait() {
  local WORKLOAD=$1
  kubectl --context=${context} -n ${namespace} rollout status $WORKLOAD --request-timeout=200
}

#-------------------------------------------------------------------------------


_setFullAdmin(){
    
    echo " Set cluster full admin"
    clusteradmin=${context}-admin

    kubectl config set-credentials "${clusteradmin}" --client-certificate="${admincrt}" --client-key="${adminkey}"
    assert_true "$?" "  ==> FAILED"

    echo "  ==> PASSED" 
}

_setContext(){
    
    echo " Set context "

    kubectl config set-context "${context}" --cluster="${context}" --user="${clusteradmin}"
    assert_true "$?" "  ==> FAILED"

    kubectl config use-context "${context}"
    assert_true "$?" "  ==> FAILED"
    
    echo "  ==> PASSED" 
}

_getLoadBalancer(){

    echo " Retrieve load balancer"

    retval=( $(kubectl -n ingress-nginx get svc ingress-nginx -o wide | grep "ingress-nginx") )

    assert_true "$?" "  ==> FAILED - ${retval}"

    assert_not_empty "${retval[0]}" "  ==> FAILED - not found namespace of service ${SERVICE_NAME}"

    loadbalancer="${retval[3]}"

    echo "Address: $loadbalancer"
    echo "  ==> PASSED"

}

_getSSLFiles(){

    echo " Get SSL files"
    if [[ ! -z "$sslkey" ]] && [[ ! -z "$sslcrt" ]] && [[ -f  "$sslkey" ]] && [[ -f  "$sslcrt" ]]; then
            echo "SSL files found"
            echo "  ==> PASSED"
            return  
    fi 

    sslkey=$SSL_KEY_FILE
    sslcrt=$SSL_CRT_FILE

    echo "Generating new SSL files ..."

    cat $OPENSSL_CONFIG_FILE | sed "s,<dns-address>,${loadbalancer},g" > "${OPENSSL_CONFIG_FILE}.temp"

    #to see all print out then just remove '> /dev/null' 
    openssl req -x509 -sha256 -newkey rsa:2048 -keyout "${sslkey}" -out "${sslcrt}" -days 365 -nodes -config "${OPENSSL_CONFIG_FILE}.temp" > /dev/null 2>&1
   
    assert_true "$?" "  ==> FAILED: openssl"

    rm -f "${OPENSSL_CONFIG_FILE}.temp"

    if [[ ! -f  "$sslkey" ]] || [[ ! -f  "$sslcrt" ]]; then
        echo "  ==> FAILED: openssl did not generate all ssl files"
        exit 1
    fi
    echo "  ==> PASSED"

}

_creatTLSSecret(){

    echo " Create TLS secret \"$SECRET\" "
    retval=$(kubectl -n ${namespace} create secret tls "${SECRET}" --cert="${sslcrt}" --key="${sslkey}" 2>&1 )

    assert_true "$?" "  ==> FAILED - ${retval}"   
    echo "  ==> PASSED"

}

_createStorageAndPVC(){

    echo " Create storage class and pvc"
    kube $BASE_PATH/k8s-yaml/storage.yaml
    assert_true "$?" "  ==> FAILED"
    echo "  ==> PASSED"
}

_createMySqlApp(){

    echo " Create mysql deployment and service"
    kube $BASE_PATH/k8s-yaml/mysql.yaml
    assert_true "$?" "  ==> FAILED"
    echo "  ==> PASSED"
}

_pollForMySqlDeploy(){

    echo " Polling for sql deployment ..."
    kube-wait deployment/${DEPLOYMENT}
    assert_true "$?" "  ==> FAILED"
    echo "  ==> PASSED"
}

_createApiDeployService(){

    echo " Create api deployment and service"
    kube $BASE_PATH/k8s-yaml/example_crud.yaml
    assert_true "$?" "  ==> FAILED"
    echo "  ==> PASSED"  
}

_pollForApiDeploy(){

    echo " Polling for api deployment ..."
    kube-wait deployment/${API_DEPLOYMENT}
    assert_true "$?" "  ==> FAILED"
    echo "  ==> PASSED"
}

_createIngress(){

    echo " Create ingress \"$INGRESS\" "

    retval=$(kube $BASE_PATH/k8s-yaml/ingress.yaml $loadbalancer 2>&1)

    assert_true "$?" "  ==> FAILED - ${retval}"
     
    echo "  ==> PASSED"

}

_waitForServiceUp(){

    echo " Polling for ingress health"
    
    for value in {1..60}
    do
        retval=$(curl -sk https://${loadbalancer}/${NAME}/users)
        retcode=$?

        if [[ ${retcode} -ne 0 ]] || [[ "${retval}" != [* ]]; then
            echo -n "."
            sleep 2
        else
            echo
            break
        fi
    done
    #echo "retval = $retval"
    if [[ ${retcode} -ne 0 ]] || [[ ! "${retval}" =~ "[" ]]; then
        echo "  ==> FAILED - Service not up after 2 minutes - $retval"
        exit 1   
    fi
    echo "  ==> PASSED"

}


_addNewEntryToUsersTable(){

    echo " Post new user to users table"
    curl -sk -XPOST https://$loadbalancer/${NAME}/user -d '{"id": "2018", "name": "ThePhantom", "username": "qa@datica.com"}' -H 'Content-Type: application/json'
    assert_true "$?" "  ==> FAILED"
    echo "  ==> PASSED"

}

_verifyDataInUsersTable(){

    echo " Retrieve users table to verify target user data existing: "
    retval=$(curl -sk https://$loadbalancer/${NAME}/users | grep "2018" | grep "ThePhantom" | grep "qa@datica.com") 
    assert_true "$?" "  ==> FAILED - data not found"
    echo "${retval}"
    echo "  ==> PASSED"

}
  
_deleteMySqlApp(){

    echo " Delete mysql app (ingress, service, deployment)"
    kubectl -n "${namespace}" delete ingress "${INGRESS}"
    assert_true "$?" "  ==> FAILED"
    kubectl -n "${namespace}" delete service "${SERVICE}"
    assert_true "$?" "  ==> FAILED"
    kubectl -n "${namespace}" delete deployment "${DEPLOYMENT}"
    sleep 5s
    assert_true "$?" "  ==> FAILED"
    echo "  ==> PASSED"

}

_cleanup(){
   
  echo " Clean up ..."

  retval=( $(kubectl -n "${namespace}" get secret | grep "${SECRET}") )
  if [[ ! -z ${retval[0]} ]]; then
      kubectl -n "${namespace}" delete secret "${SECRET}"
  fi

  retval=( $(kubectl -n "${namespace}" get ingress | grep "${INGRESS}") ) 
  if [[ ! -z ${retval[0]} ]]; then
      kubectl -n "${namespace}" delete ingress "${INGRESS}"
  fi

  retval=( $(kubectl -n "${namespace}" get service | grep "${SERVICE}") )
  if [[ ! -z ${retval[0]} ]]; then
      kubectl -n "${namespace}" delete service "${SERVICE}"
  fi

  retval=( $(kubectl -n "${namespace}" get service | grep "${API_SERVICE}") )
  if [[ ! -z ${retval[0]} ]]; then
      kubectl -n "${namespace}" delete service "${API_SERVICE}"
  fi

  retval=( $(kubectl -n "${namespace}" get deploy | grep "${DEPLOYMENT}") )
  if [[ ! -z ${retval[0]} ]]; then
      kubectl -n "${namespace}" delete deployment "${DEPLOYMENT}"
  fi

  retval=( $(kubectl -n "${namespace}" get deploy | grep "${API_DEPLOYMENT}") )
  if [[ ! -z ${retval[0]} ]]; then
      kubectl -n "${namespace}" delete deployment "${API_DEPLOYMENT}"
  fi
  
  retval=( $(kubectl -n "${namespace}" get pvc | grep "${PVC}") )
  if [[ ! -z ${retval[0]} ]]; then
      kubectl -n "${namespace}" delete pvc "${PVC}"
  fi

  retval=( $(kubectl get storageclass | grep "${STORAGECLASS}") )
  if [[ ! -z ${retval[0]} ]]; then
      kubectl delete storageclass "${STORAGECLASS}"
  fi

  retval=( $(kubectl -n "${namespace}" get serviceaccount | grep "${SERVICEACCOUNT}") )
  if [[ ! -z ${retval[0]} ]]; then
      kubectl -n "${namespace}" delete serviceaccount "${SERVICEACCOUNT}"
  fi

  retval=( $(kubectl -n "${namespace}" get rolebinding | grep "${ROLEBINDING}") )
  if [[ ! -z ${retval[0]} ]]; then
      kubectl -n "${namespace}" delete rolebinding "${ROLEBINDING}"
  fi

  retval=( $(kubectl -n "${namespace}" get role | grep "${ROLE}") )
  if [[ ! -z ${retval[0]} ]]; then
      kubectl -n "${namespace}" delete role "${ROLE}"
  fi

   echo "Done!"

}

_usage-help(){

    cat <<HELP_USAGE
    Usage: $0 <PARAMETERS>
    Parameters:
        -c, --context <Context to use for kubectl> - REQUIRED
        -a, --admincert <Admin Certifcate file> - REQUIRED
        -k, --adminkey <Admin Key file> - REQUIRED  
        -r, --sslcert <SSL Certifcate file - OPTIONAL
        -e, --sslkey <SSL Key file> - OPTIONAL
        -h, --help: usage

     Example: ./clustertest2.sh -c clustername -a /Users/myname/clustername/certs/admin.pem -k /Users/myname/clustername/certs/admin-key.pem

HELP_USAGE

#_cleanup 

TERMINATED=1 
}

_error(){
    case $1 in
        certfile )
                        echo "    Admin cert/key file(s) not found."
                        ;;
        ssl )
                        echo "    SSL cert/key file(s) not found."
                        ;;
        invalid )
                        echo "    \"$2\" is not a valid parameter"
                        ;;
        * | missing )
                        echo "    Missing or invalid parameters."
                        ;;
    esac
    _usage-help
    exit 1
}

_terminate() {
    if [ ! "$TERMINATED" ]; then
         TERMINATED=1
         _cleanup
    fi
}

trap "_terminate" 0


#------------------------------------------------------------------------------------------------------

# Main 

while [ "$1" != "" ]; do
    case $1 in
        -c | --context )
                			shift
                			context=$1
                			;;
        -a | --admincert )    
							shift
                			admincrt=$1
                			;;
        -k | --adminkey )    
							shift
                			adminkey=$1
                			;;
        -r | --sslcert )    
							shift
                			sslcrt=$1
                			;;
        -e | --sslkey )    
							shift
                			sslkey=$1
                			;;
        -h | --help )    
							_usage-help
                			exit
                			;;
        * )    				 _error invalid $1
    esac
    shift
done

if [ -z "$context" ] || [ -z "$admincrt" ] || [ -z "$adminkey" ]; then
   _error missing
fi

if [ ! -f "$admincrt" ] || [ ! -f "$adminkey" ]; then
    _error certfile
fi

#if only passing one file sslkey or sslcert then we will ignore. If passing both files but any of the file not found then will return error
if [[ ! -z "$sslkey" ]] && [[ ! -z "$sslcrt" ]]; then
    if [[ ! -f  "$sslkey" ]] || [[ ! -f  "$sslcrt" ]]; then
         _error ssl
    fi
fi

#---------------------------------------------------------------------------------------

#: <<'END'

echo
echo 'DATA RETAINING TEST'
date 
echo "Cluster: ${context}"
echo "Namespace: ${namespace}"
echo "-----------------------------------"
echo -n "1."
_setFullAdmin
echo
echo -n "2." 
_setContext
echo
echo -n "3."
_getLoadBalancer
echo
echo -n "4."
_getSSLFiles
echo
echo -n "5." 
_creatTLSSecret
echo
echo -n "6."
_createStorageAndPVC
echo
echo -n "7."
_createMySqlApp
echo
echo -n "8."
_pollForMySqlDeploy
echo
echo -n "9."
_createApiDeployService
echo
echo -n "10."
_pollForApiDeploy
echo
echo -n "11."
_createIngress
echo
echo -n "12."
_waitForServiceUp
echo
echo -n "13."
_addNewEntryToUsersTable
echo
echo -n "14."
_verifyDataInUsersTable
echo
echo -n "15."
_deleteMySqlApp
echo
echo -n "16."
_createMySqlApp
echo
echo -n "17."
_pollForMySqlDeploy
echo
echo -n "18."
_createIngress
echo
echo -n "19."
_waitForServiceUp
echo
echo -n "20."
_verifyDataInUsersTable
echo
echo -n "21."
_cleanup
echo
echo "-----------------------------------"
echo "All Tests Passed! "
echo

TERMINATED=1  

#END

#end Test


