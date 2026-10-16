//
//  AfterInvocation.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/14.
//

/// Triggered after an assistant message is added to the history.
/// This ** also**  includes messages created programmatically with `cancel` and`endTurn`.
///

/// memo: a merge of after model call and after invocation of strands
/// possible parameters
/// - response (read/write): for example, to redact part of the response.
/// - local agent
/// - resume: Set by hook callbacks to trigger a follow-up agent invocation with new input. When set, after this event's callbacks complete the agent re-enters its loop with these args as new input, under the same invocation lock.
/// - retry: retry
/// - attemptCount: the number of retry
public struct AfterInvocationEventHandler {}
