sub init()
    m.top.functionName = "doFetch"
end sub

sub doFetch()
    req = m.top.request
    if req = invalid or req.url = invalid or req.url = "" then return

    http = CreateObject("roUrlTransfer")
    http.SetUrl(req.url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.EnableEncodings(true)

    result = http.GetToString()
    if result <> invalid
        m.top.response = result
    else
        m.top.response = ""
    end if
end sub
