//
//  SafariView.swift
//  TwitterTutorial
//
//  Created by yanghj on 2023/05/02.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    // 1
    class SafariViewControllerWrapper: UIViewController {
        // 2
        private var safariViewController: SFSafariViewController?
        
        // 3
        var url: URL? {
            didSet {
                if let safariViewController = safariViewController {
                    safariViewController.willMove(toParent: self)
                    safariViewController.view.removeFromSuperview()
                    safariViewController.removeFromParent()
                    self.safariViewController = nil
                }
                
                guard let url = url else { return }
                
                let newSafariViewController = SFSafariViewController(url: url)
                addChild(newSafariViewController)
                newSafariViewController.view.frame = view.frame
                view.addSubview(newSafariViewController.view)
                newSafariViewController.didMove(toParent: self)
                self.safariViewController = newSafariViewController
            }
        }
        
        override func viewDidLoad() {
            super.viewDidLoad()
            self.url = nil
        }
    }
    
    typealias UIViewControllerType = SafariViewControllerWrapper

    // 4
    @Binding var url: URL?

    // 5
    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SafariViewControllerWrapper {
        return SafariViewControllerWrapper()
    }

    // 6
    func updateUIViewController(_ safariViewControllerWrapper: SafariViewControllerWrapper,
                                context: UIViewControllerRepresentableContext<SafariView>) {
        safariViewControllerWrapper.url = url
    }
}
