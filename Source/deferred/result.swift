//
//  Result.swift
//  async-deferred
//
//  Created by Guillaume Lessard on 2015-07-16.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

/// A Result type, approximately like everyone else has done.
///
/// The error case does not encode type beyond the Error protocol.
/// This way there is no need to ever map between error types, which mostly cannot make sense.

enum Result<Value>
{
  case value(Value)
  case error(Error)
}
