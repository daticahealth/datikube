#!/bin/bash
SCRIPT_NAME=$(echo $0 | sed s/".*\/"//)
ASSERT_SCRIPT=$(echo $0 | sed s/"$SCRIPT_NAME"/"assert.sh"/)
source "$ASSERT_SCRIPT"

INGRESS_YAML_FILE=$(echo $0 | sed s/"$SCRIPT_NAME"/"ing-hello.yaml"/)

#Test for cluster setup

#PREQUISITE: NEED TO INSTALL EXPECT FIRST: ON MAC OSX RUN 'brew install expect', ON LINUX RUN 'apt-get update && apt-get install expect'


#--------------------------Constants and global variables-------------------------------------

readonly DATIKUBE_PACKAGE=https://github.com/daticahealth/datikube/releases/download/v0.1a/datikube-v0.1a-darwin-amd64
readonly ERR_UNAUTHORIZED="error: You must be logged in to the server (Unauthorized)"
readonly BASE_PATH=$(dirname $0)
readonly CONFIGFILE=~/.kube/config
readonly DEPLOYMENT_NAME=hello
readonly SERVICE_NAME=$DEPLOYMENT_NAME
readonly INGRESS_NAME=hello-ingress
readonly INGRESS_YAML=$INGRESS_YAML_FILE
readonly INGRESS_YAML_BAK="$INGRESS_YAML_FILE.bak"
readonly SECRET_NAME=x509-hello
readonly NUM_REPLICAS=1
readonly MIN_CONTROLLERS=3
readonly MIN_WORKERS=2
readonly PROPERTY_TOKEN=users.datica.token
readonly MSG_TOKEN_SET="Property \"$PROPERTY_TOKEN\" set."
readonly MSG_DEPLOYMENT_DELETED="deployment.extensions \"$DEPLOYMENT_NAME\" deleted"
readonly SSL_KEY_FILE="$DEPLOYMENT_NAME.key"
readonly SSL_CRT_FILE="$DEPLOYMENT_NAME.crt"
readonly DEFAULT_NAMESPACE='default'

syspassword=''
clustname=''
apiserver=''
certfile=''
username=''
mempassword=''
sslkey=''
sslcrt=''
loadbalancer=''
namespace=$DEFAULT_NAMESPACE
commonname='daticaapps.com'
authhost='https://auth.datica.com'

#-----------------------------Methods-------------------------------------------------------------

_expect_credentials() {
    # Runs a command expecting credentials Email, Password, and OTP
    local COMMAND=$@
    expect -c '
        log_user 0
        spawn '"$COMMAND"'

        # Acts like a "case __ in" statement, exp_continue instructs expect to keep looking for matches
        expect {
            "Email:"    { send "'$username'\r" ; exp_continue  }
            "Password:" { send "'$mempassword'\r" ; exp_continue }
            "OTP:"      { send_user "   OTP: " ; interact -o "\r" exp_continue }

            # End condition
            EOF         { break }
        }
        
        # Wait for spawned process to exit, and retrieve exit status
        lassign [wait] pid spawnid os_error_flag value

        # Check return codes
        if {$os_error_flag == 0} {
            exit $value
        } else {
            # OS error
            puts "errno: $value"
            exit 1
        }
    '
}


_installDatikube() {

    echo " Install Datikube"

    curl -L -o ./datikube "${DATIKUBE_PACKAGE}"

    assert_true "$?" "  ==> FAILED to download datikube"

    chmod +x ./datikube
    echo -e "${syspassword}\n" | sudo -S mv ./datikube /usr/local/bin/datikube
    
    retcode=$?
    echo
    assert_true "$retcode" "  ==> FAILED to move datikube"
       
    echo "  ==> PASSED" 
}


_setContext(){
    
    echo " Datikube set-context "

    _expect_credentials 'datikube set-context "'${clustname}'" "'${apiserver}'" "'${certfile}'" --auth-host='${authhost}''

    assert_true "$?" "  ==> FAILED"

    echo "   Context set"

    expect="Switched to context \"$clustname\""

    retval=$(kubectl config use-context "${clustname}" 2>&1 | grep -o "${expect}")

    assert_eq "$expect" "$retval" "  ==> FAILED"

    echo "   $expect"

    echo "  ==> PASSED" 
}


# 'kubectl get pods' return 0 when authorized
_isAuthorized(){

    echo -n "  Is Authorized: "
   
    retval=$(kubectl -n kube-system get pods 2>&1)
    retcode=$?

    assert_true "$retcode" "\n  ==> FAILED - ${retval}"

    echo "Yes"

}

# 'kubectl get pods' return 1 with error message when unauthorized
# note: 'kubectl get deploy' will return a different msg: 'error: the server doesn't have a resource type "deploy"'
_isUnAuthorized(){

    echo -n "  Is UnAuthorized: "

    local expectcode=1
    local expecttext=$ERR_UNAUTHORIZED
   
    retval=$(kubectl -n "${namespace}" get pods 2>&1) 
    retcode=$?

    assert_eq "$expectcode" "$retcode" "\n  ==> FAILED"
    assert_eq "${expecttext}" "${retval}" "\n  ==> FAILED"

    echo  "Yes" 

}


_makeTokenExpired(){

    echo -n "  Make token expired ..."

    local current_token=$(kubectl config view -o jsonpath='{.users[?(@.name == "datica")].user.token}')

    assert_not_empty "${current_token}" "  ==> FAILED to find token!"

    local expired_token="123$current_token" 
 
    retval=$(kubectl config set $PROPERTY_TOKEN $expired_token)

    retcode=$?

    assert_true "$retcode" "\n  ==> FAILED to modify token"
    assert_eq "${MSG_TOKEN_SET}" "${retval}" "\n  ==> FAILED to set token"
    
    echo "  Done"

}


_renewalToken(){

    echo -n "  Datikube refresh ..."
    _expect_credentials 'datikube refresh --auth-host='${authhost}''

    retcode=$?
    assert_true "$retcode" "\n  ==> FAILED to refresh token"
       
    echo "  Done"

}

_verifyAuthentication(){
    
    echo " Verify authentication"
    _isAuthorized 
    _makeTokenExpired
    _isUnAuthorized 
    _renewalToken
    _isAuthorized

    echo "  ==> PASSED" 

}


_verifyMonitorPods(){

    echo " Verify controller/worker nodes and monitoring pods"

    local num_controllers=$(kubectl -n "${namespace}" get nodes | awk '{print $3}' | grep "controller" | wc -l | tr -s " ")
    echo "  -Number of controller nodes:   ${num_controllers}"

    if [[ ${num_controllers} -lt ${MIN_CONTROLLERS} ]]; then
        echo "  ==> FAILED: number of controller nodes is lower than expected minimum of ${MIN_CONTROLLERS}"
        exit 1
    fi

    local num_workers=$(kubectl -n "${namespace}" get nodes | awk '{print $3}' | grep "worker" | wc -l | tr -s " ")
    echo "  -Number of worker nodes:       ${num_workers}"
    
    if [[ ${num_workers} -lt ${MIN_WORKERS} ]]; then
        echo "  ==> FAILED: number of worker nodes is lower than expected minimum of ${MIN_WORKERS}"
        exit 1
    fi

    local num_monitors=$(kubectl -n "${namespace}" get pods -n monitoring | grep "node-exporter" | grep "Running" | wc -l | tr -s " ")
    echo "  -Number of node-exporter pods: ${num_monitors}"

    if [[ ${num_monitors} -lt $(($num_controllers+$num_workers)) ]]; then
        echo "  ==> FAILED: number of monitoring pods is less than total number of controller and worker nodes"
        exit 1
    fi 

    echo "  ==> PASSED"  

}

_createDeployment(){
    echo " Create deployment \"$DEPLOYMENT_NAME\" ... "

    retval=$(kubectl apply -f $BASE_PATH/k8s-yaml/hello-deployment.yaml 2>&1)

    retcode=$?

    assert_true "$retcode" "  ==> FAILED - ${retval}"
     
    echo "  ==> PASSED"

}

_verifyNewDeployment(){

    echo " Verify new deployment replicas and status"

    #retval is now array when putting parentheses with a space around the command.
    retval=( $(kubectl -n "${namespace}" get deploy | grep "$DEPLOYMENT_NAME") )

    assert_not_empty "${retval[0]}" "  ==> FAILED - not found deployment ${DEPLOYMENT_NAME}"

    sleep 1s 
    echo -n "   ."
    for value in {1..29}
    do
        retval=( $(kubectl -n "${namespace}" get deploy | grep "$DEPLOYMENT_NAME") )
        retcode=$?

        if [[ ${retcode} -eq 0 ]] || [[ ! ${retval[1]} -eq ${retval[2]} ]]; then
            sleep 1s
            echo -n "."
        else
            echo
            break
        fi
    done

    if [[ ${retval[1]} -ne ${NUM_REPLICAS} ]] || [[ ${retval[1]} -ne ${retval[2]} ]] || [[ ${retval[2]} -ne ${retval[3]} ]]; then
        echo
        echo "  ==> FAILED - replicas not matched or not in same state"

        echo "   EXPECTED:   ${NUM_REPLICAS}"
        echo "   DESIRED:    ${retval[1]}"
        echo "   CURRENT:    ${retval[2]}"
        echo "   UP-TO-DATE: ${retval[3]}"
        echo "   AVAILABLE:  ${retval[4]}"
        return
    fi

    echo "  ==> PASSED"
}


_createService(){
    
    echo " Create service \"$SERVICE_NAME\" ..."

    retval=$(kubectl -n "${namespace}" expose deployment "${DEPLOYMENT_NAME}" 2>&1)

    retcode=$?

    assert_true "$retcode" "  ==> FAILED - ${retval}"
     
    echo "  ==> PASSED"

}

_verifyNewService(){

    echo " Verify new service created"

    retval=( $(kubectl -n "${namespace}" get svc | grep "$SERVICE_NAME") )

    assert_not_empty "${retval[0]}" "  ==> FAILED - not found service ${DEPLOYMENT_NAME}"

    echo "  ==> PASSED"

}

_verifyServiceNameSpace(){

    echo " Verify namespace of service \"$SERVICE_NAME\" ..."
    
    retval=( $(kubectl -n "${namespace}" describe svc "$SERVICE_NAME" | grep "Namespace:") )
    retcode=$?

    assert_true "$retcode" "  ==> FAILED - ${retval}"

    assert_not_empty "${retval[1]}" "  ==> FAILED - not found namespace of service ${SERVICE_NAME}"

    assert_eq "$namespace" "${retval[1]}" "  ==> FAILED - namespace not matched"

    echo "  Namespace: $namespace"
    echo "  ==> PASSED"

}

#Note: Openssl requires either CommonName or Email. But it won't take too long commonName (max 64 chars) so can not pass in load balancer address. 
#Will use daticaapps.com by now
_getSSLFiles(){

    echo " Get SSL files"
    if [[ ! -z "$sslkey" ]] && [[ ! -z "$sslcrt" ]]; then
        if [[ ! -f  "$sslkey" ]] || [[ ! -f  "$sslcrt" ]]; then
            echo "  ==> FAILED: missing ssl key file and/or ssl cert file as specified"
            exit 1
        else
            echo "  SSL files found"
            echo "  ==> PASSED"
            return
        fi
    fi 

    sslkey=$SSL_KEY_FILE
    sslcrt=$SSL_CRT_FILE

    echo "  Generating new SSL files ..."

    #to see all print out then just remove '> /dev/null' 
    (echo -e "\n\n\n\n\n\n$commonname\n\n") | openssl req -newkey rsa:2048 -nodes -keyout "$sslkey" -x509 -days 365 -out "$sslcrt" > /dev/null 2>&1
   
    retcode=$?
    assert_true "$retcode" "  ==> FAILED: openssl may need better answer to prompts"

    if [[ ! -f  "$sslkey" ]] || [[ ! -f  "$sslcrt" ]]; then
            echo "  ==> FAILED: openssl did not generate all ssl files"
            exit 1
    fi
    echo "  ==> PASSED"

}

_creatTLSSecret(){

    echo " Create TLS secret \"$SECRET_NAME\" ..."
    
    if [[ -z "$sslkey" ]] || [[ -z "$sslcrt" ]]; then
        sslkey=$SSL_KEY_FILE
        sslcrt=$SSL_CRT_FILE
    fi

    #generic secret - tested ok as well 
    #retval=$(kubectl create secret generic "$SECRET_NAME" --from-file="$sslcrt" --from-file="$sslkey" 2>&1 )
   
    retval=$(kubectl -n "${namespace}" create secret tls "$SECRET_NAME" --cert="$sslcrt" --key="$sslkey" 2>&1 )
    retcode=$?

    assert_true "$retcode" "  ==> FAILED - ${retval}"
     
    echo "  ==> PASSED"

}

_verifyNewTLSSecret(){

    echo " Verify new secret created"

    retval=( $(kubectl -n "${namespace}" get secret | grep "$SECRET_NAME") )

    assert_not_empty "${retval[0]}" "  ==> FAILED - not found service ${SECRET_NAME}"

    echo "  ==> PASSED"

}

_getLoadBalancer(){

    echo " Retrieve Load Balancer ..."

    retval=( $(kubectl -n ingress-nginx get svc ingress-nginx -o wide | grep "ingress-nginx") )
    retcode=$?

    assert_true "$retcode" "  ==> FAILED - ${retval}"

    assert_not_empty "${retval[0]}" "  ==> FAILED - not found namespace of service ${SERVICE_NAME}"

    loadbalancer="${retval[3]}"

    echo "  Address: $loadbalancer"
    echo "  ==> PASSED"

}

_updateIngressYaml(){

    echo " Update Ingress YAML file"

    echo -n "  Adjust Load Balancer address:"
    local default_address=$(cat "$INGRESS_YAML" | grep "host:" | awk '{print $3}')

    if [[ -z ${default_address} ]]; then
        echo
        echo "  ==> FAILED - Unable to find default host address from ingress yaml"
        exit 1
    fi

    sed -i .bak "s,${default_address},${loadbalancer},g" "$INGRESS_YAML"

    retcode=$?

    if [[ ${retcode} -ne 0 ]]; then
        echo "  ==> FAILED"
        exit 1
    fi
    echo " Done!"
    
    echo "  ==> PASSED"   

}

_resetIngressYamlFile(){

    echo "Reset Ingress YAML file"
    if [[ -f "$INGRESS_YAML_BAK" ]]; then
        mv -f ${INGRESS_YAML_BAK} ${INGRESS_YAML}
    fi
}


_createIngress(){

    echo " Create ingress \"$INGRESS_NAME\" ..."

    cat $INGRESS_YAML | sed s,"{{ hostname }}",${loadbalancer},g | kubectl -n ${namespace} apply -f -

    assert_true "$?" "  ==> FAILED"
     
    echo "  ==> PASSED"

}

_verifyNewIngress(){

    echo " Verify new ingress resource created"

    retval=( $(kubectl -n "${namespace}" get ing | grep "$INGRESS_NAME") )

    assert_not_empty "${retval[0]}" "  ==> FAILED - not found service $INGRESS_NAME"

    echo "  ==> PASSED"

}

_testService(){

    echo " Test service url by curl"

    sleep 1s
    echo -n "  ."

    for value in {1..59}
    do
        retval=$(curl -Is --insecure "https://$loadbalancer" | grep "HTTP/2" 2>&1)
        retcode=$?
        echo "Retval is $retval"

        if [[ ${retcode} -ne 0 ]] || [[ ! "${retval}" =~ "200" ]]; then
            sleep 1s
            echo  -n "."
        else
            echo
            break
        fi
    done

    assert_true "$retcode" "  ==> FAILED - Service was not up after 60 seconds"
       
    if [[ ! "${retval}" =~ "HTTP/2" ]] || [[ ! "${retval}" =~ "200" ]]; then
        echo "  ==> FAILED - ${retval}"
        exit 1   
    else
        echo "   $(echo "$retval" | grep "HTTP")"
    fi
       
    echo "  ==> PASSED"

}

_deleteIngress(){

    echo " Delete ingress \"$INGRESS_NAME\" ..."

    retval=$(kubectl -n "${namespace}" delete ing "${INGRESS_NAME}" 2>&1)

    retcode=$?

    assert_true "$retcode" "  ==> FAILED - ${retval}"
     
    echo "  ==> PASSED"

}

_verifyIngressDeleted(){

    echo " Verify ingress deleted"

    retval=( $(kubectl -n "${namespace}" get ing | grep "${INGRESS_NAME}") )

    assert_empty "${retval[0]}" "  ==> FAILED - still see service ${INGRESS_NAME}"

    echo "  ==> PASSED"

}

_deleteService(){

    echo " Delete service \"$SERVICE_NAME\" ..."

    retval=$(kubectl -n "${namespace}" delete svc "${SERVICE_NAME}" 2>&1)

    retcode=$?

    assert_true "$retcode" "  ==> FAILED - ${retval}"
     
    echo "  ==> PASSED"

}

_verifyServiceDeleted(){

    echo " Verify service deleted"

    retval=( $(kubectl -n "${namespace}" get svc | grep "${SERVICE_NAME}") )

    assert_empty "${retval[0]}" "  ==> FAILED - still see service ${SERVICE_NAME}"

    echo "  ==> PASSED"

}

_deleteDeployment(){

    echo " Delete deployment \"$DEPLOYMENT_NAME\" ... "

    retval=$(kubectl -n "${namespace}" delete deployment "${DEPLOYMENT_NAME}" 2>&1)

    retcode=$?

    assert_true "$retcode" "  ==> FAILED - ${retval}"
     
    echo "  ==> PASSED"

}

_verifyDeploymentDeleted(){

    echo " Verify deployment deleted"

    retval=( $(kubectl -n "${namespace}" get deploy | grep "${DEPLOYMENT_NAME}") )

    assert_empty "${retval[0]}" "  ==> FAILED - still see deployment ${DEPLOYMENT_NAME}"

    echo "  ==> PASSED"
}

_deleteTLSSecret(){

    echo " Delete TLS secret \"$SECRET_NAME\" ... "

    retval=$(kubectl -n "${namespace}" delete secret "${SECRET_NAME}" 2>&1)

    retcode=$?

    assert_true "$retcode" "  ==> FAILED - ${retval}"
     
    echo "  ==> PASSED"

}

_verifyTLSSecretDeleted(){

    echo " Verify secret deleted"

    retval=( $(kubectl -n "${namespace}" get secret | grep "${SECRET_NAME}") )

    assert_empty "${retval[0]}" "  ==> FAILED - still see secret ${SECRET_NAME}"

    echo "  ==> PASSED"
}


#once we start the port-forward, we can do something using curl to see if it returns appropriately and maybe just pull the <title>
# tag or something out of the headers and go with that for the time being
_portForwardKibana(){

    echo " Port-forward for Kibana logging service "

    #retval=$(kubectl --context=datica-test port-forward -n logging service/kibana 8001:5601 & 2>&1)
    kubectl port-forward -n logging service/kibana 8001:5601 &

    retcode=$?

    assert_true "$retcode" "  ==> FAILED"

    echo "  ==> PASSED"
}

_verifyLogging(){

    echo " Verify Kibana web page "

    echo "   Wait for forwarding service to start up"

    sleep 2s
    echo -n "   ."

    for value in {1..29}
    do
        retval=$(curl -Is "http://localhost:8001" | grep "HTTP\|kibana" 2>&1)
        retcode=$?

        if [[ ${retcode} -ne 0 ]] || [[ ! "${retval}" =~ "200 OK" ]] || [[ ! "${retval}" =~ "kibana" ]]; then
            sleep 2s
            echo  -n "."
        else
            echo
            #echo "   Service is up!"
            break
        fi
    done

    assert_true "$retcode" "  ==> FAILED - Service was not up after 60 seconds"
       
    if [[ ! "${retval}" =~ "200 OK" ]] || [[ ! "${retval}" =~ "kibana" ]]; then
        echo "  ==> FAILED Kibana service or HTTP - ${retval}"
        exit 1
       
    else
        echo "   $(echo "$retval" | grep "kibana")"
        echo "   $(echo "$retval" | grep "HTTP")"
    fi
       
    echo "  ==> PASSED"
}


_killPortForward(){

    echo " Kill port-forward process "
    
    pkill kubectl

    retcode=$?

    assert_true "$retcode" "  ==> FAILED"

    echo "  ==> PASSED"

}



# Clean up any left over stuff from failed test
_cleanup(){

    echo "Clean up ..."

    retval=( $(kubectl -n "${namespace}" get secret | grep "${SECRET_NAME}") )
    if [[ ! -z ${retval[0]} ]]; then
        kubectl -n "${namespace}" delete secret "${SECRET_NAME}"
    fi

    retval=( $(kubectl -n "${namespace}" get ingress | grep "${INGRESS_NAME}") ) 
    if [[ ! -z ${retval[0]} ]]; then
        kubectl -n "${namespace}" delete ingress "${INGRESS_NAME}"
    fi

    retval=( $(kubectl -n "${namespace}" get service | grep "${SERVICE_NAME}") )
    if [[ ! -z ${retval[0]} ]]; then
        kubectl -n "${namespace}" delete service "${SERVICE_NAME}"
    fi

    retval=( $(kubectl -n "${namespace}" get deploy | grep "${DEPLOYMENT_NAME}") )
    if [[ ! -z ${retval[0]} ]]; then
        kubectl -n "${namespace}" delete deployment "${DEPLOYMENT_NAME}"
    fi

    retval=( $(ps -ax | grep kubectl) )
    if [[ ${retval[3]} == "kubectl" ]] && [[ ${retval[4]} == "port-forward" ]]; then
        pkill kubectl
    fi

   echo "Done!"

}

_usage-help(){

    cat <<HELP_USAGE
    Usage: 
    $0 -s <system password> -u <member username> -p <member password> -c <cluster name> -a <api load balancer url> -f <ca certificate file path> [-k <ssl key file path> -r <ssl crt file path>] --auth-host <datica auth host (default: https://auth.datica.com)>

    Auth Hosts:
        - Prod: https://auth.datica.com
        - Dev:  https://auth-sandbox.catalyzeapps.com

    Sample command:
    ./clustertest1.sh -s 'mysystempassword' -u 'mymember@datica.com' -p 'mymemberpassword' -c datica-test -a https://datica-test-apiserver-1803012743.us-east-2.elb.amazonaws.com/ -f /Users/myname/Downloads/datica-test-product-ca.pem --auth-host https://auth-sandbox.catalyzeapps.com

HELP_USAGE
TERMINATED=1 

}

_error(){
    case $1 in
        certfile )
                        echo "    CA Certificate not found."
                        ;;
        ssl )
                        echo "    SSL file(s) not found."
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
        -s )    shift
                syspassword=$1
                ;;
        -u )    shift
                username=$1
                ;;
        -p )    shift
                mempassword=$1
                ;;
        -c )    shift
                clustname=$1
                ;;
        -a )    shift
                apiserver=$1
                ;;
        -f )    shift
                certfile=$1
                ;;      
        -k )    shift
                sslkey=$1
                ;;
        -r )    shift
                sslcrt=$1
                ;; 
        --auth-host )
                shift
                authhost=$1
                ;; 
            
        -h )    _usage-help
                exit
                ;;
        * )     _error invalid $1
    esac
    shift
done

if [ -z "$syspassword" ] || [ -z "$username" ] || [ -z "$mempassword" ] || [ -z "$clustname" ] || [ -z "$apiserver" ] || [ -z "$certfile" ]; then
   _error missing
fi

if [ ! -f "$certfile" ]; then
    _error certfile
fi

#if only passing one file sslkey or sslcert then we will ignore. If passing both files but any of the file not found then will return error
if [[ ! -z "$sslkey" ]] && [[ ! -z "$sslcrt" ]]; then
    if [[ ! -f  "$sslkey" ]] || [[ ! -f  "$sslcrt" ]]; then
         _error ssl
    fi
fi

# Check if fluentd psp exists
kubectl get psp | grep fluentd > /dev/null 2>&1
FLUENTD_PSP=$?

#-------------------------------------


#: <<'END'
echo
echo "CLUSTER INIT TESTS"
date 
echo
echo "I. AUTHENTICATE BY DATIKUBE"
echo -n "1." 
_installDatikube
echo
echo -n "2." 
_setContext
echo
echo -n "3."
_verifyAuthentication
echo
echo "II. LIST RESOURCES (MONITORING PODS)"
echo -n "1."
_verifyMonitorPods
echo
echo "III. CREATE DEPLOYMENT"
echo -n "1."
_createDeployment
echo
echo -n "2."
_verifyNewDeployment
echo
echo "IV. CREATE SERVICE"
echo -n "1."
_createService
echo
echo -n "2."
_verifyNewService
echo
echo -n "3."
_verifyServiceNameSpace
echo
echo "V. CREATE TLS SECRET"
echo -n "1."
_getSSLFiles
echo
echo -n "2."
_creatTLSSecret
echo
echo -n "3."
_verifyNewTLSSecret
echo
echo "VI. GET LOAD BALANCER"
echo -n "1."
_getLoadBalancer
echo
echo "VII. CREATE INGRESS RESOURCE"
echo -n "1."
_createIngress
echo
echo -n "2."
_verifyNewIngress
echo
echo -n "3. "
_resetIngressYamlFile
echo
echo "VIII. TEST NEW SERVICE URL"
echo -n "1."
_testService
echo
echo "IX. DELETE INGRESS RESOURCE"
echo -n "1."
_deleteIngress
echo
echo -n "2."
_verifyIngressDeleted
echo
echo "X. DELETE SECRET"
echo -n "1."
_deleteTLSSecret
echo
echo -n "2."
_verifyTLSSecretDeleted
echo
echo "XI. DELETE SERVICE"
echo -n "1."
_deleteService
echo
echo -n "2."
_verifyServiceDeleted
echo
echo "XII. DELETE DEPLOYMENT"
echo -n "1."
_deleteDeployment
echo
echo -n "2."
_verifyDeploymentDeleted
echo
echo "XIII. ACCESS LOGGING"
echo -n "1."
_portForwardKibana
echo
echo -n "2."
_verifyLogging
echo
echo -n "3."
_killPortForward
echo
echo "XIV. POD SECURITY POLICIES"
echo "1. Verify cluster PSPs"
if [ $FLUENTD_PSP -gt 0 ]; then
  $(dirname $0)/psp_test.sh --stage "psp-rules workloads"
else
  $(dirname $0)/psp_test.sh --stage "psp-rules workloads" --using-vpns
fi
echo
echo "All Tests Passed! "
echo

#END

TERMINATED=1

#end Test




