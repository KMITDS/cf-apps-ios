//
//  CFApi.swift
//  CF Apps
//
//  Created by Dwayne Forde on 2015-07-12.
//  Copyright (c) 2015 Dwayne Forde. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

class CFApi {
    class func info(apiURL: String, success: (json: JSON) -> Void, error: () -> Void) {
        Alamofire.request(CF.Info(apiURL))
            .validate()
            .responseJSON { (_, _, result) in
                if (result.isSuccess) {
                    let json = JSON(result.value!)
                    success(json: json)
                } else {
                    error()
                }
        }
    }

    class func login(authURL: String, username: String, password: String, success: () -> Void, error: () -> Void) {
        Alamofire.request(CF.Login(authURL, username, password))
            .validate()
            .responseJSON { (_, _, result) in
                if (result.isSuccess) {
                    let json = JSON(result.value!)
                    let token = json["access_token"].string
                    CF.oauthToken = token
                    success()
                } else {
                    error()
                }
        }
    }
    
    class func orgs(success: (json: JSON) -> Void, error: (statusCode: Int) -> Void) {
        if (!CFSession.isEmpty()) {
            Alamofire.request(CF.Orgs())
                .validate()
                .responseJSON { (_, response, result) in
                    responseHandler(response!, result: result, success: success, error: error, recover: {
                        self.orgs(success, error: error)
                    })
            }
        } else {
            self.retryLogin({
                self.orgs(success, error: error)
            })
        }
    }
    
    class func apps(orgGuid: String, page: Int, success: (json: JSON) -> Void, error: (statusCode: Int) -> Void) {
        if (!CFSession.isEmpty()) {
            Alamofire.request(CF.Apps(orgGuid, page))
                .validate()
                .responseJSON { (_, response, result) in
                    responseHandler(response!, result: result, success: success, error: error, recover: {
                        self.apps(orgGuid, page: page, success: success, error: error)
                    })
            }
        }
    }
    
    class func appSummary(appGuid: String, success: (json: JSON) -> Void, error: (statusCode: Int) -> Void) {
        if (!CFSession.isEmpty()) {
            Alamofire.request(CF.AppSummary(appGuid))
                .validate()
                .responseJSON { (_, response, result) in
                    responseHandler(response!, result: result, success: success, error: error, recover: {
                        self.appSummary(appGuid, success: success, error: error)
                    })
            }
        }
    }
    
    class func appStats(appGuid: String, success: (json: JSON) -> Void, error: (statusCode: Int) -> Void) {
        if (!CFSession.isEmpty()) {
            Alamofire.request(CF.AppStats(appGuid))
                .validate()
                .responseJSON { (_, response, result) in
                    responseHandler(response!, result: result, success: success, error: error, recover: {
                        self.appStats(appGuid, success: success, error: error)
                    })
            }
        }
    }
    
    
    class func spaces(appGuids: [String], success: (json: JSON) -> Void, error: (statusCode: Int) -> Void) {
        if (!CFSession.isEmpty()) {
            Alamofire.request(CF.Spaces(appGuids))
                .validate()
                .responseJSON  { (req, response, result) in
                    responseHandler(response!, result: result, success: success, error: error, recover: {
                        self.spaces(appGuids, success: success, error: error)
                    })
                    
            }
        }
    }
    
    class private func responseHandler(response: NSHTTPURLResponse, result: Result<AnyObject>, success: (json: JSON) -> Void, error: (statusCode: Int) -> Void, recover: () -> Void) {
        
        if (result.isSuccess) {
            let json = JSON(result.value!)
            success(json: json)
        } else {
            if (response.statusCode == 401) {
                self.retryLogin(recover)
            }
            error(statusCode: response.statusCode)
        }
    }
    
    class private func retryLogin(success: () -> Void) {
        let (authURL, username, password) = Keychain.getCredentials()
        
        self.login(authURL!, username: username!, password: password!, success: success, error: {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let loginViewController: LoginViewController = storyboard.instantiateViewControllerWithIdentifier("LoginView") as! LoginViewController
            let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
            loginViewController.authError = true
            appDelegate.window!.rootViewController = loginViewController
            CFSession.reset()
        })
    }
}