//
//  TwitterAPI.swift
//  TwitterTutorial
//  https://medium.com/codex/how-to-implement-twitter-api-v1-authentication-in-swiftui-2dc4e93f7a82
//  Created by yanghj on 2023/05/02.
//

import SwiftUI
import Combine
import CommonCrypto


class TwitterAPI: NSObject, ObservableObject {
    @Published var authorizationSheetIsPresented = false
    @Published var authorizationURL: URL?
    @Published var user: User?
    
    // 로그인 후 사용할 유저 데이터
    struct User {
        let ID: String
        let screenName: String
    }
    
    struct ClientCredentials {
        static let APIKey = ""
        static let APIKeySecret = ""
        static let CallbackURLScheme = "://"
    }
    
    struct TemporaryCredentials {
        let requestToken: String
        let requestTokenSecret: String
    }
    
    // 엑세스 토큰 구조
    struct TokenCredentials {
        let accessToken: String
        let accessTokenSecret: String
    }
    
    enum OAuthError: Error {
        case unknown
        case urlError(URLError)
        case httpURLResponse(Int)
        case cannotDecodeRawData
        case cannotParseResponse
        case unexpectedResponse
        case failedToConfirmCallback
    }
    
    // 엑세스 토큰 저장
    private var tokenCredentials: TokenCredentials?
    
    private var subscriptions: [String: AnyCancellable] = [:]
    
    func authorize() {
        guard !self.authorizationSheetIsPresented else { return }
        self.authorizationSheetIsPresented = true
        
        self.subscriptions["oAuthRequestTokenSubscriber"] =
        self.oAuthRequestTokenPublisher()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished: ()
                case.failure(_):
                    // Handle Errors
                    self.authorizationSheetIsPresented = false
                }
                self.subscriptions.removeValue(forKey: "oAuthRequestTokenSubscriber")
            }, receiveValue: { [weak self] temporaryCredentials in
                guard let self = self else { return }
                
                guard let authorizationURL = URL(string: "https://api.twitter.com/oauth/authorize?oauth_token=\(temporaryCredentials.requestToken)")
                else { return }
                
                self.authorizationURL = authorizationURL
                
                self.subscriptions["onOAuthRedirect"] =
                    self.onOAuthRedirect
                        .sink(receiveValue: { [weak self] url in
                            guard let self = self else { return }
                            
                            self.subscriptions.removeValue(forKey: "onOAuthRedirect")
                            
                            self.authorizationSheetIsPresented = false
                            self.authorizationURL = nil
                            
                            if let parameters = url.query?.urlQueryItems {
                                guard let oAuthToken = parameters["oauth_token"],
                                      let oAuthVerifier = parameters["oauth_verifier"]
                                else {
                                    return
                                }
                                
                                if oAuthToken != temporaryCredentials.requestToken {
                                    return
                                }
                                
                                print(oAuthToken)
                                print(oAuthVerifier)
                                
                                self.subscriptions["oAuthAccessTokenSubscriber"] =
                                    self.oAuthAccessTokenPublisher(temporaryCredentials: temporaryCredentials,
                                                                   verifier: oAuthVerifier) // 1
                                    .receive(on: DispatchQueue.main) // 2
                                    .sink(receiveCompletion: { _ in // 3
                                        // Error handler
                                    }, receiveValue: { [weak self] (tokenCredentials, user) in // 4
                                        guard let self = self else { return }
                                        
                                        // 5
                                        self.subscriptions.removeValue(forKey: "oAuthRequestTokenSubscriber")
                                        self.subscriptions.removeValue(forKey: "onOAuthRedirect")
                                        self.subscriptions.removeValue(forKey: "oAuthAccessTokenSubscriber")
                                        
                                        self.tokenCredentials = tokenCredentials // 6
                                        // 여기서 이 값을 가지고 user 정보를 더 획득 해야함.
                                        self.user = user // 7
                                    })
                                
                            }
                        })
            })
        
    }
    
    lazy var onOAuthRedirect = PassthroughSubject<URL, Never>()
    
    // 서명 기본 문자열 만들기
    private func oAuthSignatureBaseString(httpMethod: String,
                                          baseURLString: String,
                                          parameters: [URLQueryItem]) -> String {
        var parameterComponents: [String] = []
        for parameter in parameters {
            let name = parameter.name.oAuthURLEncodedString
            let value = parameter.value?.oAuthURLEncodedString ?? ""
            parameterComponents.append("\(name)=\(value)")
        }
        let parameterString = parameterComponents.sorted().joined(separator: "&")
        return httpMethod + "&" +
            baseURLString.oAuthURLEncodedString + "&" +
            parameterString.oAuthURLEncodedString
    }
    
    // Signing Key 생성
    private func oAuthSigningKey(consumerSecret: String,
                                 oAuthTokenSecret: String?) -> String {
        if let oAuthTokenSecret = oAuthTokenSecret {
            return consumerSecret.oAuthURLEncodedString + "&" +
                oAuthTokenSecret.oAuthURLEncodedString
        } else {
            return consumerSecret.oAuthURLEncodedString + "&"
        }
    }
    
    
    // 서명 만들기
    private func oAuthSignature(httpMethod: String,
                                baseURLString: String,
                                parameters: [URLQueryItem],
                                consumerSecret: String,
                                oAuthTokenSecret: String? = nil) -> String {
        let signatureBaseString = oAuthSignatureBaseString(httpMethod: httpMethod,
                                                           baseURLString: baseURLString,
                                                           parameters: parameters)

        let signingKey = oAuthSigningKey(consumerSecret: consumerSecret,
                                         oAuthTokenSecret: oAuthTokenSecret)

        return signatureBaseString.hmacSHA1Hash(key: signingKey)
    }
    
    // 인증 헤더 생성
    private func oAuthAuthorizationHeader(parameters: [URLQueryItem]) -> String {
        var parameterComponents: [String] = []
        for parameter in parameters {
            let name = parameter.name.oAuthURLEncodedString
            let value = parameter.value?.oAuthURLEncodedString ?? ""
            parameterComponents.append("\(name)=\"\(value)\"")
        }
        return "OAuth " + parameterComponents.sorted().joined(separator: ", ")
    }
    
    // 인증 요청 토큰 얻기
    func oAuthRequestTokenPublisher() -> AnyPublisher<TemporaryCredentials, OAuthError> {
        
        let request = (baseURLString: "https://api.twitter.com/oauth/request_token",
                       httpMethod: "POST",
                       consumerKey: ClientCredentials.APIKey,
                       consumerSecret: ClientCredentials.APIKeySecret,
                       callbackURLString: "\(ClientCredentials.CallbackURLScheme)")
        
        // 유효한 URL인지 확인
        guard let baseURL = URL(string: request.baseURLString) else {
            return Fail(error: OAuthError.urlError(URLError(.badURL)))
                .eraseToAnyPublisher()
        }
        
        // 필요한 파라메터 정의
        var parameters = [
            URLQueryItem(name: "oauth_callback", value: request.callbackURLString),
            URLQueryItem(name: "oauth_consumer_key", value: request.consumerKey),
            URLQueryItem(name: "oauth_nonce", value: UUID().uuidString),
            URLQueryItem(name: "oauth_signature_method", value: "HMAC-SHA1"),
            URLQueryItem(name: "oauth_timestamp", value: String(Int(Date().timeIntervalSince1970))),
            URLQueryItem(name: "oauth_version", value: "1.0")
        ]
        
        // 서명을 만들어서 파라메터에 정의
        let signature = oAuthSignature(httpMethod: request.httpMethod,
                                       baseURLString: request.baseURLString,
                                       parameters: parameters,
                                       consumerSecret: request.consumerSecret)
        
        parameters.append(URLQueryItem(name: "oauth_signature", value: signature))
        
        // 패킷 보낼 헤더 부터 생성 및 설정
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = request.httpMethod
        urlRequest.setValue(oAuthAuthorizationHeader(parameters: parameters),
                            forHTTPHeaderField: "Authorization")
        
        return
            // 트위터 서버로 데이터 전송
            // dataTaskPublisher -> Combine api
            URLSession.shared.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response -> TemporaryCredentials in // 성공해야만 데이터를 아래로 내려보냄
                guard let response = response as? HTTPURLResponse
                else { throw OAuthError.unknown }
                
                guard response.statusCode == 200
                else { throw OAuthError.httpURLResponse(response.statusCode)}
                
                guard let parameterString = String(data: data, encoding: .utf8)
                else { throw OAuthError.cannotDecodeRawData }
                
                if let parameters = parameterString.urlQueryItems {
                    guard let oAuthToken = parameters["oauth_token"],
                          let oAuthTokenSecret = parameters["oauth_token_secret"],
                          let oAuthCallbackConfirmed = parameters["oauth_callback_confirmed"]
                    else {
                        throw OAuthError.unexpectedResponse
                    }
                    
                    if oAuthCallbackConfirmed != "true" {
                        throw OAuthError.failedToConfirmCallback
                    }
                    
                    return TemporaryCredentials(requestToken: oAuthToken, requestTokenSecret: oAuthTokenSecret)
                } else {
                    throw OAuthError.cannotParseResponse
                }
            }
            .mapError { error -> OAuthError in
                switch (error) {
                case let oAuthError as OAuthError:
                    return oAuthError
                default:
                    return OAuthError.unknown
                }
            }
            // AnyPublisher 형태로 리턴해주기 때문에 어떤 자료형이 들어오든 처리 가능
            .eraseToAnyPublisher()
    }
    
    func oAuthAccessTokenPublisher(temporaryCredentials: TemporaryCredentials, verifier: String) -> AnyPublisher<(TokenCredentials, User), OAuthError> {
        // 1
        let request = (baseURLString: "https://api.twitter.com/oauth/access_token",
                       httpMethod: "POST",
                       consumerKey: ClientCredentials.APIKey,
                       consumerSecret: ClientCredentials.APIKeySecret)
        
        // 2
        guard let baseURL = URL(string: request.baseURLString) else {
            return Fail(error: OAuthError.urlError(URLError(.badURL)))
                .eraseToAnyPublisher()
        }
        
        // 3
        var parameters = [
            URLQueryItem(name: "oauth_token", value: temporaryCredentials.requestToken),
            URLQueryItem(name: "oauth_verifier", value: verifier),
            URLQueryItem(name: "oauth_consumer_key", value: request.consumerKey),
            URLQueryItem(name: "oauth_nonce", value: UUID().uuidString),
            URLQueryItem(name: "oauth_signature_method", value: "HMAC-SHA1"),
            URLQueryItem(name: "oauth_timestamp", value: String(Int(Date().timeIntervalSince1970))),
            URLQueryItem(name: "oauth_version", value: "1.0")
        ]
        
        // 4
        let signature = oAuthSignature(httpMethod: request.httpMethod,
                                       baseURLString: request.baseURLString,
                                       parameters: parameters,
                                       consumerSecret: request.consumerSecret,
                                       oAuthTokenSecret: temporaryCredentials.requestTokenSecret)
        
        // 5
        parameters.append(URLQueryItem(name: "oauth_signature", value: signature))
        
        // 6
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = request.httpMethod
        urlRequest.setValue(oAuthAuthorizationHeader(parameters: parameters),
                            forHTTPHeaderField: "Authorization")
        
        return
        // 7
        URLSession.shared.dataTaskPublisher(for: urlRequest)
            // 8
            .tryMap { data, response -> (TokenCredentials, User) in
                // 9
                guard let response = response as? HTTPURLResponse
                else { throw OAuthError.unknown }
                
                // 10
                guard response.statusCode == 200
                else { throw OAuthError.httpURLResponse(response.statusCode) }
                
                // 11
                // oauth_token=1653569118153613314-96We7puFpkY47cixaX0x6HGjv2fyn0&oauth_token_secret=97vhbJkEVeiSNd9gXfAq3Jxt4sk6ItpWHz3C5M609ZRA5&user_id=1653569118153613314&screen_name=huijunyang85788
                guard let parameterString = String(data: data, encoding: .utf8)
                else { throw OAuthError.cannotDecodeRawData }
                
                // 12
                if let parameters = parameterString.urlQueryItems {
                    // 13
                    guard let oAuthToken = parameters.value(for: "oauth_token"),
                          let oAuthTokenSecret = parameters.value(for: "oauth_token_secret"),
                          let userID = parameters.value(for: "user_id"),
                          let screenName = parameters.value(for: "screen_name")
                    else {
                        throw OAuthError.unexpectedResponse
                    }
                    
                    // 14
                    return (TokenCredentials(accessToken: oAuthToken,
                                            accessTokenSecret: oAuthTokenSecret),
                            User(ID: userID,
                                 screenName: screenName))
                } else {
                    throw OAuthError.cannotParseResponse
                }
            }
            // 15
            .mapError { error -> OAuthError in
                switch (error) {
                case let oAuthError as OAuthError:
                    return oAuthError
                default:
                    return OAuthError.unknown
                }
            }
            // 16
            .receive(on: DispatchQueue.main)
            // 17
            .eraseToAnyPublisher()
    }
    
}

extension CharacterSet {
    static var urlRFC3986Allowed: CharacterSet {
        CharacterSet(charactersIn: "-_.~").union(.alphanumerics)
    }
}

extension String {
    var oAuthURLEncodedString: String {
        self.addingPercentEncoding(withAllowedCharacters: .urlRFC3986Allowed) ?? self
    }
}

extension String {
    var urlQueryItems: [URLQueryItem]? {
        URLComponents(string: "://?\(self)")?.queryItems
    }
}

extension Array where Element == URLQueryItem {
    func value(for name: String) -> String? {
        return self.filter({$0.name == name}).first?.value
    }
    
    subscript(name: String) -> String? {
        return value(for: name)
    }
}

extension String {
    func hmacSHA1Hash(key: String) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
               key,
               key.count,
               self,
               self.count,
               &digest)
        return Data(digest).base64EncodedString()
    }
}
