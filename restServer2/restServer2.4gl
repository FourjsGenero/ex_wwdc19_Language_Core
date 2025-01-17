################################################################################
#
# FOURJS_START_COPYRIGHT(U,2019)
# Property of Four Js*
# (c) Copyright Four Js 2019. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
#
# Four Js and its suppliers do not warrant or guarantee that these samples
# are accurate and suitable for your purposes. Their inclusion is purely for
# information purposes only.
# FOURJS_END_COPYRIGHT
#
################################################################################
import com
import util

# Application utilities
import fgl appUtility
import fgl http

# Application logging
import fgl logger

# Cookie validation
import fgl cookieFactory

# Interface request library
import fgl interfaceRequest

# Services API
import fgl pingFactory
import fgl interfaceFactory

# Additional app logging variable
define applicationError string

################################################################################
#+
#+ Application: Application MAIN
#+
#+ Description: RESTful services server to hand incoming requests.
#+
main
    define listenerStatus, listenerTimeout, authenticateUser integer

    define incomingRequest com.HTTPServiceRequest
    define responsePayload responseType

    whenever any error call errorHandler
    defer interrupt

    try
        # Initialize application
        call appUtility.initialize()

        # Register service resources
        call serverInitialize()

        call logger.logEvent(logger.C_LOGMSG, ARG_VAL(0), sfmt("Line: %1", __LINE__), "Starting server")
        call com.WebServiceEngine.Start()
        call logger.logEvent(logger.C_LOGMSG, ARG_VAL(0), sfmt("Line: %1", __LINE__), "Started")

    catch
        # Startup failed for some reason
        let applicationError = "<MAIN>RESTServer startup failure"
        call logger.logEvent(logger.C_LOGMSG, ARG_VAL(0), sfmt("Line: %1", __LINE__), "Start failed.")
        call errorHandler()
    end try

    # Set server timeout.  Default -1(infinite)
    let listenerTimeout = fgl_getenv("GWS_SERVERTIMEOUT")
    let listenerTimeout = iif(listenerTimeout is not null, listenerTimeout, -1)
    call logger.logEvent(logger.C_LOGMSG, ARG_VAL(0), sfmt("Line: %1", __LINE__), sfmt("Server timeout: %1", listenerTimeout))


    # Set authentication option.  Default: FALSE(0)
    let authenticateUser = fgl_getenv("GWS_AUTHENTICATE")
    let authenticateUser = iif(authenticateUser is not null, authenticateUser, false)

    # Listen for REST requests and process them
    while true
        call logger.logEvent(logger.C_LOGMSG, ARG_VAL(0), sfmt("Line: %1", __LINE__), "The server is listening...")

        # Process incoming requests
        let incomingRequest = com.WebServiceEngine.handleRequest(listenerTimeout, listenerStatus)

        # Check for timeout or socket error
        call checkListenerStatus(listenerStatus)

        # Parse the request
        call interfaceRequest.setRestRequestInfo(incomingRequest)

        # Initialize the response
        call interfaceRequest.initRequestResponse()

        # Check if authentication is enforced
        if ( authenticateUser ) then
            # Check for credentials and set authorizatioin cookie
            if (interfaceRequest.getRestResource() = "ping") then
                if (pingFactory.isValidCredential()) then
                    # Create a session cookie(s)
                    call cookieFactory.bakeCookies("GeneroAuthZ", "/", true)
                    # Set the cookie(s) in the resonse
                    call interfaceRequest.setResponseCookies(cookieFactory.getCookies())
                end if

            else
                # Check authorization token
                if cookieFactory.checkCookies(interfaceRequest.getSessionCookie()) then
                    call interfaceFactory.processRequest()
                else
                    # Set authorization error
                    call interfaceRequest.setResponse(
                        C_HTTP_NOTAUTH,
                        "ERROR",
                        D_HTTPSTATUSDESC[C_HTTP_NOTAUTH],
                        "Invalid session token or token not found.  Check token or re-login.")
                end if
            end if

        # Authentication is not enforced
        else
            call interfaceFactory.processRequest()
        end if

        # Process request and send the request response
        call interfaceRequest.getResponse() returning responsePayload.*
        call interfaceRequest.sendRequestResponse(responsePayload.code, null, util.JSON.stringify(responsePayload))

        if int_flag <> 0 then
            let int_flag = 0
            exit while
        end if
    end while

    call logger.logEvent(logger.C_LOGMSG, ARG_VAL(0), sfmt("Line: %1", __LINE__), "The server was stopped, normally.")
    call programExit(0)

end main

################################################################################
#+
#+ Method: serviceInitialize()
#+
#+ Description: Initialize web service configuration
#+
private function serverInitialize() returns()
    #define serviceModule, servicePath string

    # Set response maximumn length.  Default -1(unlimited)
    call com.WebServiceEngine.SetOption("maximumresponselength", getServerCofiguration("GWS_MAXLENGTH"))

    # Set read/write timout.  Default is infinite(-1)
    call com.WebServiceEngine.SetOption("readwritetimeout", getServerCofiguration("GWS_RWTIMEOUT"))

    # Set connection timeout.  Default is infinit(-1)
    call com.WebServiceEngine.SetOption("connectiontimeout", getServerCofiguration("GWS_CONNECTTIMEOUT"))

{
    # Example URL: http://server/config/ws/r/rest/officestore
    #     GWS_MODULE = officestore
    #     GWS_BASEPATH = http://server/config/ws/r/rest
    let serviceModule = fgl_getenv("GWS_MODULE")
    let servicePath = fgl_getenv("GWS_BASEPATH")
    if serviceModule.trimWhiteSpace().getLength() = 0 or servicePath.trimWhiteSpace().getLength() = 0 then
        call logger.logEvent(logger.C_LOGMSG, ARG_VAL(0), sfmt("Line: %1", __LINE__), "Check service configuration settings.")
        call appUtility.programExit(1)
    end if
}
    return
end function

################################################################################
#+
#+ Method: getServerCofiguration()
#+
#+ Description: Returns server timout settings from environment
#
#+ @code
#+ CALL getServerCofiguration(envVar)
#+
#+ @param envVar : STRING : id of the environment variable
#+
#+ @returnType INTEGER
#+
function getServerCofiguration(thisSetting string) returns(integer)
    define thisValue integer
    let thisValue = fgl_getenv(thisSetting)
    call logger.logEvent(logger.C_LOGMSG, ARG_VAL(0), sfmt("Line: %1", __LINE__), sfmt("ENV::%1::%2", thisSetting, thisValue))

    return iif(thisValue is not null, thisValue, -1)
end function

################################################################################
#+
#+ Method: checkListenerStatus()
#+
#+ Description: Evaluate and handle the Web services listener status
#+
#+ @code
#+ CALL getServerCofiguration(listenerStatus)
#+
#+ @param envVar : INTEGER : status code returned by web server
#+
#+ @returnType NONE
#
function checkListenerStatus(listenerStatus integer) returns()
    define statusMessage string

    case listenerStatus
        when 1
            exit case
        when 0
            let statusMessage = "Request processed."
        when -1
            let statusMessage = "Timeout reached."
        when -2
            let statusMessage = "Disconnected from application server."
        when -3
            let statusMessage = "Client Connection lost."
        when -4
            let statusMessage = "Server interrupted with Ctrl-C."
        when -8
            let statusMessage = "Internal HTTP Error."
        when -9
            let statusMessage = "Unsupported operation."
        when -10
            let statusMessage = "Internal server error."
        when -14
            let statusMessage = "Incoming request overflow."
        when -15
            let statusMessage = "Server was not started."
        when -16
            let statusMessage = "Request still in progress."
        when -18
            let statusMessage = "Input request handler error."
        when -19
            let statusMessage = "Output request handler error."
        when -23
            let statusMessage = "Deserialization error."
        when -29
            let statusMessage = "Cookie error."
        when -35
            let statusMessage = "No such REST resource found."
        when -36
            let statusMessage = "Missing REST parameter."
        when -38
            let statusMessage = "Open API Error."
        when -39
            let statusMessage = "Content Type Ctx Incompatible."
        when -40
            let statusMessage = "Scope Missing."
        otherwise
            let statusMessage = "Unexpected server error ."
    end case

    if listenerStatus != 1 then
        # Application server timeout
        if listenerStatus == -15575 then
            call logger.logEvent(
                logger.C_LOGERROR,
                ARG_VAL(0),
                sfmt("Line: %1", __LINE__),
                "REST service listener disconnected by application server.")
            call appUtility.programExit(1)
        else
            #com.WebServiceEngine error code
            if listenerStatus is null then
                call logger.logEvent(logger.C_LOGMSG, ARG_VAL(0), sfmt("Line: %1", __LINE__), "REST Listener status is NULL")
            else
                call logger.logEvent(
                    logger.C_LOGMSG,
                    ARG_VAL(0),
                    sfmt("Line: %1", __LINE__),
                    sfmt("%1:%2 %3", listenerStatus, statusMessage, SQLCA.SQLERRM))
            end if
            call appUtility.programExit(0)
        end if
    end if
    return
end function

################################################################################
#+
#+ Method: errorHandler()
#+
#+ Description: Standard error function to handle error display
#+
private function errorHandler() returns()
    define errorMessage string

    let errorMessage =
        "\nSTATUS                : ",
        STATUS using "<<<<&",
        "\nSQLERRMESSAGE         : ",
        sqlerrmessage,
        "\nSQLSTATE              : ",
        sqlstate using "<<<<&",
        "\nSQLERRM               : ",
        SQLCA.SQLERRM,
        "\nSQLCODE               : ",
        SQLCA.SQLCODE using "<<<<&",
        "\nSQLERRM               : ",
        SQLCA.SQLCODE using "<<<<&",
        "\nSQLERRD[2]            : ",
        SQLCA.SQLERRD[2] using "<<<<&",
        "\nSQLERRD[3]            : ",
        SQLCA.SQLERRD[3] using "<<<<&",
        "\nOFFSET TO ERROR IN SQL: ",
        SQLCA.SQLERRD[5] using "<<<<&",
        "\nROWID FOR LAST INSERT : ",
        SQLCA.SQLERRD[6] using "<<<<&"

    #Optional app debug logging
    &ifdef APP_LOGGING
        LET errorMessage = errorMessage || "\nAPPERROR              : ", applicationError
    &endif

    call com.WebServiceEngine.SetRestError(500, null)
    call logger.logEvent(logger.C_LOGERROR, ARG_VAL(0), sfmt("Line: %1", __LINE__), errorMessage)
    call appUtility.programExit(1)

    return
end function
