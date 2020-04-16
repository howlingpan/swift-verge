//
// Copyright (c) 2019 muukii
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import os

public protocol SubscriptionType {
  func dispose()
}

public final class EventEmitterSubscription: Hashable, SubscriptionType {
  public static func == (lhs: EventEmitterSubscription, rhs: EventEmitterSubscription) -> Bool {
    lhs === rhs
  }
  
  private weak var owner: EventEmitterType?
  
  fileprivate init(owner: EventEmitterType) {
    self.owner = owner
  }
  
  public func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }
  
  public func dispose() {
    owner?.remove(self)
  }
}

public protocol EventEmitterType: AnyObject {
  func remove(_ token: EventEmitterSubscription)
}

/// Instead of Combine
public final class EventEmitter<Event>: EventEmitterType {
  
  private var __publisher: Any?
  
  private let lock = VergeConcurrency.UnfairLock()
  
  private var subscribers: [EventEmitterSubscription : (Event) -> Void] = [:]
  
  public init() {
    
  }
      
  public func accept(_ event: Event) {
    let targets: Dictionary<EventEmitterSubscription, (Event) -> Void>.Values
    lock.lock()
    targets = subscribers.values
    lock.unlock()
    targets.forEach {
      $0(event)
    }
  }
  
  @discardableResult
  public func add(_ eventReceiver: @escaping (Event) -> Void) -> EventEmitterSubscription {
    let token = EventEmitterSubscription(owner: self)
    lock.lock()
    subscribers[token] = eventReceiver
    lock.unlock()
    return token
  }
  
  public func remove(_ token: EventEmitterSubscription) {
    lock.lock()
    subscribers.removeValue(forKey: token)
    lock.unlock()
  }
}

#if canImport(Combine)

import Combine

extension EventEmitter {
  
  @available(iOS 13, macOS 10.15, *)
  public struct Publisher: Combine.Publisher {
           
    public typealias Output = Event
    
    public typealias Failure = Never
    
    private let eventEmitter: EventEmitter<Event>
    
    public init(eventEmitter: EventEmitter<Event>) {
      self.eventEmitter = eventEmitter
    }

    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
      
      let anySubscriber = AnySubscriber(subscriber)
      let subscription = Subscription(subscriber: anySubscriber, eventEmitter: eventEmitter)
      subscriber.receive(subscription: subscription)      
    }
    
  }
  
  @available(iOS 13, macOS 10.15, *)
  public struct Subscription: Combine.Subscription {
        
    public let combineIdentifier: CombineIdentifier = .init()
    
    private let subscriber: AnySubscriber<Event, Never>
    private let eventEmitterSubscription: EventEmitterSubscription
    private weak var eventEmitter: EventEmitter<Event>?
    
    init(subscriber: AnySubscriber<Event, Never>, eventEmitter: EventEmitter<Event>) {
      
      self.subscriber = subscriber
      self.eventEmitter = eventEmitter
      
      self.eventEmitterSubscription = eventEmitter.add { (event) in
        _ = subscriber.receive(event)
      }
    }

    public func request(_ demand: Subscribers.Demand) {
      
    }
    
    public func cancel() {
      eventEmitter?.remove(eventEmitterSubscription)
    }
            
  }
  
}

extension EventEmitter {
  
  @available(iOS 13, macOS 10.15, *)
  public var publisher: Publisher {
    if let publisher = __publisher as? Publisher {
      return publisher
    }
    let newPublisher = Publisher(eventEmitter: self)
    __publisher = newPublisher
    return newPublisher
  }
  
}

#endif
