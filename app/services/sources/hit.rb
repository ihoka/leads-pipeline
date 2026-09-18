module Sources
  # A single verbatim result from a source. Adapters return these and nothing
  # else: no scoring, no normalisation, no AI.
  Hit = Data.define(:source_uid, :payload, :observed_at)
end
