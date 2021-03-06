//
//  CacheManager.swift
//  PrebidMobile
//
//  Created by L.D. Deurman on 30/05/2019.
//  Copyright © 2019 AppNexus. All rights reserved.
//

import Foundation
import WebKit
import UIKit

public class CacheManager: NSObject, UIWebViewDelegate {

    private static var cache: CacheManager?

    private weak var delegate: UIWebViewDelegate!
    private var webView: UIWebView!
    private var startTime: Double!
    private var isWebViewFinished = false
    private var webViewCompletionHandlers: [CompletionHandler] = []

    public init(window: CacheManagerWindowProtocol) {
        super.init()

        self.startTime = Date().timeIntervalSince1970
        self.webView = UIWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        self.webView.delegate = self
        window.addSubview(webView)

        let elapsedTime = Date().timeIntervalSince1970 - startTime
        Log.debug("CacheManager initialization took " + elapsedTime.description + " ms")
        self.webViewCompletionHandlers.append({
            self.cleanupBids()
            self.setupBidCleanup()
        })
        setupCache()
    }

    public static func configure() {
        if (CacheManager.cache == nil) {
            CacheManager.cache = CacheManager(window: UIApplication.shared.keyWindow!)
        }
    }

    private func debugLocalStorageInfo() {
        if let result = self.webView.stringByEvaluatingJavaScript(from: "window.location.host + ' has ' + localStorage.length + ' localStorage items'") {
            Log.debug(result)
        } else {
            Log.debug("JS localStorage info debug didn't return a value")
        }
    }

    private func cacheBids(bids: [Bid], completion:@escaping CompletionHandler) {

        var jsObjects: [String] = []
        for bid in bids {
            if let jsonString = bid.getJSON() {
                jsObjects.append(String(format: "{creative: '%@', bid: %@}", bid.getCreative(), jsonString))
            }
        }

        let arrayStr = String(format: "var items = [" + jsObjects.joined(separator: ",")) + "]"
        let script =  "" +
            "\n" +
            arrayStr +
            "\n" +
            "for (var i = 0; i < items.length; i++) {\n" +
            "  var item = items[i];\n" +
            "  localStorage.setItem(item.creative, JSON.stringify(item.bid));\n" +
            "}" + "\n\n"

        let dateStarted = Date()

        self.webView.stringByEvaluatingJavaScript(from: script)
        let elapsedTime = self.getTimeElapsed(startTime: dateStarted)
        Log.debug("CacheManager did cache bids in " + elapsedTime.description + " ms")
        completion()

        debugLocalStorageInfo()

    }

    func saveBids(bids: [Bid], onQueue: DispatchQueue = DispatchQueue.main, completion:@escaping CompletionHandler) {
        onQueue.async {
            if self.isWebViewFinished {
                self.cacheBids(bids: bids, completion: completion)
            } else {
                self.webViewCompletionHandlers.append({
                    self.cacheBids(bids: bids, completion: completion)
                })
            }
        }
    }

    static func getCacheManager() -> CacheManager {
        return CacheManager.cache!
    }

    private func setupCache() {
        if let url = URL(string: "https://pubads.g.doubleclick.net") {
            webView.loadHTMLString("<html></html>", baseURL: url)
        }
    }

    private func getTimeElapsed(startTime: Date? = nil) -> Double {

        var startTimeMillis: Double = 0
        if startTime != nil {
            startTimeMillis = startTime!.timeIntervalSince1970
        } else {
            startTimeMillis = self.startTime
        }

        let elapsedTime = Date().timeIntervalSince1970 - startTimeMillis
        return elapsedTime

    }

    public func webViewDidFinishLoad(_ webView: UIWebView) {
        let elapsedTime = Date().timeIntervalSince1970 - startTime
        Log.debug("CacheManager webView loaded in " + elapsedTime.description + " ms")

        self.isWebViewFinished = true

        for webViewCompletion in self.webViewCompletionHandlers {
            webViewCompletion()
        }
        self.webViewCompletionHandlers = []
    }

    private func cleanupBids() {
        let startDate = Date()
        let now = startDate.timeIntervalSince1970 * 1000
        let nowString = String(now)
        let removeCacheScript = "var currentTime = " + nowString + ";" +
            "\nvar toBeDeleted = [];\n" +
            "\n" +
            "for(i = 0; i< localStorage.length; i ++) {\n" +
            "\tif (localStorage.key(i).startsWith('Prebid_')) {\n" +
            "\t\tcreatedTime = localStorage.key(i).split('_')[2];\n" +
            "\t\tif (( currentTime - createdTime) > 270000){\n" +
            "\t\t\ttoBeDeleted.push(localStorage.key(i));\n" +
            "\t\t}\n" +
            "\t}\n" +
            "}\n" +
            "\n" +
            "for ( i = 0; i< toBeDeleted.length; i ++) {\n" +
            "\tlocalStorage.removeItem(toBeDeleted[i]);\n" +
        "}"

        self.webView.stringByEvaluatingJavaScript(from: removeCacheScript)
        let elapsedTime = self.getTimeElapsed(startTime: startDate)
        Log.debug("CacheManager did do cleanup in " + elapsedTime.description + " ms")
    }

    private func setupBidCleanup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: {
            self.cleanupBids()
            self.setupBidCleanup()
        })
    }

}

public protocol CacheManagerWindowProtocol {
    func addSubview(_ view: UIView)
}

extension UIView: CacheManagerWindowProtocol { }
