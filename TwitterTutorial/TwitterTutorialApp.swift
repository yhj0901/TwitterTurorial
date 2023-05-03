//
//  TwitterTutorialApp.swift
//  TwitterTutorial
//
//  Created by yanghj on 2023/05/02.
//

import SwiftUI

@main
struct TwitterTutorialApp: App {
    @StateObject var twitterAPI = TwitterAPI()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(twitterAPI)
                .onOpenURL{ url in
                    // toptoonplus://?oauth_token=C6YTSwAAAAABQeE2AAABh99tnXQ&oauth_verifier=Inzuozlund5xtulQEVwLNMI8EeXLIQZS
                    guard let urlScheme = url.scheme,
                          let callbackURL = URL(string: "\(TwitterAPI.ClientCredentials.CallbackURLScheme)"),
                          let callbackURLScheme = callbackURL.scheme
                    else { return }
                    
                    guard urlScheme.caseInsensitiveCompare(callbackURLScheme) == .orderedSame
                    else { return }
                    
                    twitterAPI.onOAuthRedirect.send(url)
                }
        }
    }
}
