//
//  ContentView.swift
//  TwitterTutorial
//
//  Created by yanghj on 2023/05/02.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var twitterAPI: TwitterAPI
    
    var body: some View {
        VStack {
            if let screenName = twitterAPI.user?.screenName {
                Text("Welcome").font(.largeTitle)
                Text(screenName).font(.largeTitle)
            } else {
                Button("Signin with Twitter", action: {
                    twitterAPI.authorize()
                    
                })
            }
        }
        .sheet(isPresented: $twitterAPI.authorizationSheetIsPresented) {
            SafariView(url: $twitterAPI.authorizationURL)
        }
    }
    
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
}
