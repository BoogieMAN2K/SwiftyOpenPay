//
//  SwiftyOpenPay.swift
//  SwiftyOpenPay
//
//  Created by Oscar Swanros on 1/13/16.
//  Copyright © 2016 Pacific3. All rights reserved.
//

public let OpenPayErrorDomain = "com.openpay.ios.lib"

extension SwiftyOpenPay.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .MalformedResponse: return "Could not parse server's response."
        }
    }
}

public struct SwiftyOpenPay {
    // MARK: - Internal declarations
    internal static let api_url           = "https://api.openpay.mx/"
    internal static let sandbox_api_url   = "https://sandbox-api.openpay.mx/"
    internal static let api_version       = "v1"
    
    internal var URLBase: String {
        let base = sandboxMode ? SwiftyOpenPay.sandbox_api_url : SwiftyOpenPay.api_url
        
        return base + SwiftyOpenPay.api_version + "/" + merchantId + "/"
    }
    
    
    // MARK: - SwiftyOpenPay supporting data types
    public struct Configuration {
        public let merchantId: String
        public let apiKey: String
        public let sandboxMode: Bool
        public let verboseMode: Bool
        
        public init(
            merchantId: String,
            apiKey: String,
            sandboxMode: Bool = false, 
            verboseMode: Bool = false
            ) {
                self.merchantId  = merchantId
                self.apiKey      = apiKey
                self.sandboxMode = sandboxMode
                self.verboseMode = verboseMode
        }
    }
    
    public enum Error: Int, ErrorConvertible {
        case MalformedResponse = 1
        
        public var code: Int {
            return self.rawValue
        }
        
        public var errorDescription: String {
            return self.description
        }
        
        public var domain: String {
            return OpenPayErrorDomain
        }
    }
    
    
    // MARK: - Private Properties
    private static let internalQueue = OperationQueue()
    
    
    // MARK: - Public Properties
    public let merchantId: String
    public let apiKey: String
    public let sandboxMode: Bool
    public let verboseMode: Bool
    
    
    // MARK: - Public Initializers
    public init(
        merchantId: String,
        apiKey: String, 
        sandboxMode: Bool = false,
        verboseMode: Bool = false
        ) {
            self.merchantId  = merchantId
            self.apiKey      = apiKey
            self.sandboxMode = sandboxMode
            self.verboseMode = verboseMode
    }
    
    public init(configuration: Configuration) {
        merchantId  = configuration.merchantId
        apiKey      = configuration.apiKey
        sandboxMode = configuration.sandboxMode
        verboseMode = configuration.verboseMode
    }
    
    
    // MARK: - Public Methods
    public func createTokenWithCard(
        card: Card,
        completion: Token -> Void,
        error: NSError -> Void
        ) throws {
            try card.isValid()
            
            guard let url = NSURL(string: URLBase + "tokens/") else {
                return
            }
            
            let request = requestForURL(
                url,
                method: .POST,
                payload: card.backingData()
            )
            
            sendRequest(
                request, 
                type: Token.self,
                completionClosure: completion, 
                errorClosure: error
            )
    }
    
    public func getTokenWithId(
        id: String,
        completion: Token -> Void,
        error: NSError -> Void
        ) {
            guard let url = NSURL(string: URLBase + "tokens/" + id) else {
                return
            }
            
            let request = requestForURL(url, method: .GET)
            
            sendRequest(
                request,
                type: Token.self,
                completionClosure: completion, 
                errorClosure: error
            )
    }
}


// MARK: - Private Methods
extension SwiftyOpenPay {
    private func requestForURL(
        url: NSURL,
        method: HTTPMethod, 
        payload: [String:AnyObject]? = nil
        ) -> NSURLRequest {
            let request = NSMutableURLRequest(
                URL: url,
                cachePolicy: NSURLRequestCachePolicy.UseProtocolCachePolicy,
                timeoutInterval: 30
            )
            
            request.setValue(
                "application/json;revision=1.1",
                forHTTPHeaderField: "Accept"
            )
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            request.setValue(
                "OpenPay-iOS/1.0.0",
                forHTTPHeaderField: "User-Agent"
            )
            request.HTTPMethod = method.rawValue
            
            let authStr = "\(apiKey):" + ""
            let data = authStr.dataUsingEncoding(NSASCIIStringEncoding)
            guard
                let value = data?.base64EncodedStringWithOptions(
                    NSDataBase64EncodingOptions.EncodingEndLineWithCarriageReturn
                ) else {
                    fatalError("Could not generate authentication credentials.")
            }
            request.setValue(
                "Basic \(value)",
                forHTTPHeaderField: "Authorization"
            )
            
            if let payload = payload {
                do {
                    let data = try NSJSONSerialization.dataWithJSONObject(
                        payload,
                        options: .PrettyPrinted
                    )
                    request.HTTPBody = data
                    if verboseMode { print("Payload:\n\(payload)") }
                } catch {}
            }
            
            if verboseMode { print("Request to send:\n\(request)") }
            
            return request
    }
    
    private func sendRequest<T: JSONParselable>(
        request: NSURLRequest,
        type: T.Type,
        completionClosure: (T -> Void)? = nil,
        errorClosure: (NSError -> Void)? = nil
        ) {
            let session = NSURLSession(
                configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration()
            )
            let task = session.dataTaskWithRequest(request) { data, reponse, error in
                guard let data = data where error === nil else {
                    if let error = error {
                        if self.verboseMode { print("Got error from server:\n\(error)") }
                        errorClosure?(error)
                    }
                    return
                }
                
                var json = [String:AnyObject]?()
                
                do {
                    json = try NSJSONSerialization.JSONObjectWithData(
                        data,
                        options: .MutableLeaves
                        ) as? [String:AnyObject]
                } catch let jsonError as NSError {
                    errorClosure?(jsonError)
                }
                
                if self.verboseMode { print("Parsed server response:\n\(json)") }
                
                guard
                    let _json = json,
                    let model = type.withData(_json)
                    else {
                        errorClosure?(
                            NSError(
                                error: ErrorSpecification(
                                    ec: Error.MalformedResponse
                                )
                            )
                        )
                        return
                }
                
                completionClosure?(model)
            }
            
            let taskOp = URLSessionTaskOperation(task: task)
            taskOp.addObserver(NetworkActivityObserver())
            
            SwiftyOpenPay.internalQueue.addOperation(taskOp)
    }
}
