// Sends one command line to the running demo (Crema/App/DemoRemote.swift).
import Foundation

let line = CommandLine.arguments.dropFirst().joined(separator: " ")
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.colatte.crema.demo"), object: line, userInfo: nil, deliverImmediately: true
)
