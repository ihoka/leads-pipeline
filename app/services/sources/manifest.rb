module Sources
  # Declares what an adapter accepts, what it returns, what it costs, and what
  # risk it carries. The registry surfaces this so the UI can warn before
  # enabling a ToS-risky or paid source.
  Manifest = Data.define(:accepted_params, :returned_fields, :cost_cents_per_call, :risk_level)
end
