let
  # Transitional callable contract: the current conductor invokes agents and
  # sequential workflows with one non-empty textual objective and emits textual
  # assistant content. Do not model these as generic structured objects until
  # WorkflowDefinition has real typed value/binding dataflow.
  inputSchema = {
    type = "string";
    minLength = 1;
  };
  outputSchema = {
    type = "string";
  };

  descriptor = kind: id: description: {
    inherit id kind description;
    input_schema = inputSchema;
    output_schema = outputSchema;
    capabilities = [ ];
    policy.requires_permission = false;
  };

  agents = {
    coordinator =
      descriptor "agent" "agent.coordinator"
        "Coordinate bounded specialist work and preserve explicit decisions without editing the codebase.";
    scout =
      descriptor "agent" "agent.scout"
        "Inspect concrete repository and ecosystem evidence without changing code.";
    planner =
      descriptor "agent" "agent.planner"
        "Convert settled intent into an executable plan without implementing it.";
    architect =
      descriptor "agent" "agent.architect"
        "Model boundaries, ownership, invariants, and architectural tradeoffs without implementing them.";
    implementer =
      descriptor "agent" "agent.implementer"
        "Own bounded code, test, and instrumentation mutations needed to satisfy the settled objective.";
    tester =
      descriptor "agent" "agent.tester"
        "Act as a read-only evidence analyst: run existing feedback, reproduce behavior, and distinguish observations from hypotheses without editing files.";
    critic =
      descriptor "agent" "agent.critic"
        "Challenge engineering quality, architecture, and evidence independently without editing the codebase.";
    verifier =
      descriptor "agent" "agent.verifier"
        "Verify conformance to requested behavior and acceptance evidence independently without editing the codebase.";
    finalizer =
      descriptor "agent" "agent.finalizer"
        "Synthesize established evidence without inventing new findings or editing implementation files.";
    qa_synthesizer =
      descriptor "agent" "agent.qa-synthesizer"
        "Synthesize independent QA evidence while preserving provenance and disagreement without editing implementation files.";
  };

  step = agent: task: {
    callable = agents.${agent}.id;
    objective = "${agents.${agent}.description} ${task} for the current workflow objective.";
  };

  workflow = id: title: steps: {
    descriptor = descriptor "workflow" id title;
    policy = "sequential";
    inherit steps;
  };

  qaReviewSteps = [
    (step "coordinator" "Coordinate independent QA branches and keep their evidence separate")
    (step "scout" "Review repository structure, correctness, duplication, and integration seams")
    (step "tester" "Run or interpret deterministic checks and identify coverage gaps")
    (step "architect" "Review architecture, module boundaries, ownership, and migration containment")
    (step "critic" "Review trust boundaries, unsafe assumptions, and concrete security risks")
    (step "qa_synthesizer" "Produce one prioritized QA report from the independent review evidence")
  ];

  workflows = [
    (workflow "workflow.implement" "Phenix implementation" [
      (step "planner" "Produce the minimum executable plan appropriate to the requested change")
      (step "implementer" "Apply the plan using existing abstractions and keep the change bounded")
      (step "verifier" "Independently verify requested behavior, deterministic checks, and relevant regressions")
    ])

    (workflow "workflow.qa" "Phenix QA" qaReviewSteps)

    (workflow "workflow.qa-fix" "Phenix QA and fix" (
      qaReviewSteps
      ++ [
        (step "planner" "Turn actionable QA findings into a bounded repair plan and keep the plan empty when there is nothing to fix")
        (step "implementer" "Apply only actionable repairs justified by the QA report")
        (step "verifier" "Verify repaired findings independently and guard against regressions")
        (step "finalizer" "Produce the final QA-and-fix handoff with evidence and unresolved findings")
      ]
    ))

    (workflow "workflow.design" "Phenix design" [
      (step "scout" "Inspect requirements, constraints, and reusable mechanisms")
      (step "planner" "Develop viable alternatives and an executable decision plan")
      (step "architect" "Evaluate ownership, interfaces, data flow, and invariants")
      (step "critic" "Challenge assumptions, tradeoffs, and failure modes")
      (step "finalizer" "Produce the decision-oriented design handoff")
    ])

    (workflow "workflow.migrate" "Phenix migration" [
      (step "scout" "Inventory contracts, providers, consumers, and compatibility surfaces affected by the migration")
      (step "planner" "Produce an ordered migration plan with explicit expand-migrate-contract boundaries where required")
      (step "implementer" "Execute the migration and remove superseded paths when consumers have moved")
      (step "critic" "Audit migrated consumers, obsolete interfaces, duplication, and migration containment")
      (step "finalizer" "Produce the migration handoff and remaining follow-ups")
    ])

    (workflow "workflow.refactor" "Phenix refactor" [
      (step "scout" "Capture public behavior, invariants, existing tests, and dependency shape before structural change")
      (step "architect" "Define intended ownership, module boundaries, and dependency direction")
      (step "implementer" "Apply the behavior-preserving refactor and remove obsolete duplication")
      (step "critic" "Review architecture, semantic preservation, and whether the refactor actually reduces complexity")
      (step "finalizer" "Produce the refactor handoff with behavioral evidence")
    ])

    (workflow "workflow.security" "Phenix security review" [
      (step "scout" "Map entry points, assets, privilege boundaries, and externally controlled data")
      (step "architect" "Model ownership, trust boundaries, abuse paths, and security invariants")
      (step "critic" "Validate concrete security risks adversarially and reject speculative findings without evidence")
      (step "finalizer" "Produce the evidence-backed security handoff")
    ])

    (workflow "workflow.ui-change" "Phenix UI change" [
      (step "scout" "Inspect interaction, rendering, focus, input, and state-update paths")
      (step "architect" "Specify layout, focus, input, feedback, and update invariants before implementation")
      (step "implementer" "Implement the UI change using the highest appropriate existing UI abstractions")
      (step "tester" "Exercise existing framework-appropriate UI scenarios and interaction regressions")
      (step "critic" "Review interaction quality, predictability, hierarchy, and state consistency")
      (step "finalizer" "Produce the UI change handoff with scenario evidence")
    ])

    (workflow "workflow.debug" "Evidence-driven diagnosis" [
      (step "tester" "Reproduce the failure with the narrowest existing feedback path and capture the exact observable evidence")
      (step "tester" "Derive the smallest reproducing scenario without editing production or test files")
      (step "critic" "Rank falsifiable root-cause hypotheses and state the evidence that would discriminate them")
      (step "tester" "Design the narrowest diagnostic experiment or instrumentation needed to discriminate the leading hypotheses")
      (step "implementer" "Add only the bounded diagnostic instrumentation or harness change required by the experiment")
      (step "tester" "Run the diagnostic experiment and determine which hypotheses the resulting evidence supports or rejects")
      (step "implementer" "Remove temporary diagnostics as appropriate and apply the smallest root-cause repair justified by the evidence")
      (step "verifier" "Re-run the reproducer and relevant regressions and verify durable regression coverage exists where appropriate")
      (step "finalizer" "Summarize reproduction, causal evidence, repair, and residual uncertainty")
    ])

    (workflow "workflow.review" "Independent code review" [
      (step "critic" "Review only engineering quality, architecture, maintainability, correctness risks, tests, and duplication")
      (step "verifier" "Review only conformance to the stated request, specification, and acceptance criteria")
    ])

    (workflow "workflow.research" "Source-oriented research" [
      (step "scout" "Investigate repository code, tests, documentation, and history")
      (step "scout" "Investigate authoritative upstream documentation, specifications, releases, and prior art")
      (step "scout" "Investigate risks, constraints, edge cases, and counterexamples")
      (step "critic" "Challenge contradictions, source quality, unsupported conclusions, and missing counterevidence")
      (step "finalizer" "Produce a source-oriented handoff separating facts, inferences, disagreement, and uncertainty")
    ])

    (workflow "workflow.grill" "Alignment grilling" [
      (step "scout" "Resolve questions already answered by code, tests, documentation, and existing decisions")
      (step "coordinator" "Stress-test one unresolved decision at a time and keep prerequisite decisions ordered")
      (step "architect" "Normalize settled vocabulary and identify only durable architectural decisions")
      (step "finalizer" "Produce the durable decision and context handoff without implementing the feature")
    ])

    (workflow "workflow.spec" "Specification synthesis" [
      (step "scout" "Recover settled intent, project vocabulary, constraints, and existing behavior")
      (step "architect" "Identify the highest stable implementation and acceptance seams")
      (step "planner" "Write an implementation-independent specification with invariants, acceptance criteria, and non-goals")
      (step "verifier" "Verify the specification is grounded, testable, and free of invented product decisions")
    ])

    (workflow "workflow.tickets" "Tracer-bullet decomposition" [
      (step "architect" "Identify prerequisite structural changes that make the implementation easy before making the easy change")
      (step "planner" "Decompose work into independently verifiable vertical slices with explicit blocking edges")
      (step "critic" "Reject needless fragmentation, oversized tickets, and horizontal slicing unless migration requires it")
      (step "finalizer" "Produce the blocker-first ticket frontier with acceptance evidence and dependencies")
    ])

    (workflow "workflow.tdd" "Test-driven development" [
      (step "tester" "Identify the smallest durable test seam, expected assertion, and intended failing reason without editing files")
      (step "implementer" "Add the focused regression test and prove it fails for the intended missing behavior before changing production behavior")
      (step "implementer" "Make the smallest coherent production change that turns the focused test green without weakening the test")
      (step "implementer" "Improve boundaries and remove duplication while keeping focused feedback green")
      (step "verifier" "Run focused and surrounding validation and verify requested behavior without regression")
    ])

    (workflow "workflow.architecture" "Architecture deepening" [
      (step "scout" "Map concrete code paths, abstractions, duplicated knowledge, naming, and dependency direction")
      (step "architect" "Find opportunities to deepen modules, reduce exposed concepts, and reuse stronger existing abstractions")
      (step "critic" "Challenge migration cost, accidental abstraction, coupling, and whether the proposal actually simplifies the system")
      (step "planner" "Produce a prioritized architecture plan with tradeoffs, migration containment, and validation seams")
    ])

    (workflow "workflow.domain-model" "Domain modeling" [
      (step "scout" "Collect terminology, entities, operations, invariants, and contradictory names from code and documentation")
      (step "architect" "Choose canonical terms and define their semantic boundaries and relationships")
      (step "critic" "Reject aliases, overloaded terms, and abstractions that do not reduce conceptual ambiguity")
      (step "finalizer" "Produce settled domain vocabulary and unresolved semantic conflicts")
    ])

    (workflow "workflow.wayfinder" "Long-horizon wayfinding" [
      (step "scout" "Identify constraints, unknowns, irreversible decisions, dependencies, and available evidence")
      (step "planner" "Build a compact decision and investigation map and identify the current frontier")
      (step "architect" "Resolve the highest-leverage architecture and domain decisions that evidence can settle")
      (step "verifier" "Verify the frontier names remaining uncertainty and is ready for specification and decomposition")
    ])
  ];

  allowedEfforts = [
    "low"
    "medium"
    "high"
  ];
  target =
    provider: model: effort:
    assert builtins.elem effort allowedEfforts;
    {
      backend = "phenix";
      inherit provider model;
      inference = { inherit effort; };
    };

  roles = [
    "coordinator"
    "scout"
    "planner"
    "architect"
    "implementer"
    "tester"
    "verifier"
    "critic"
    "finalizer"
    "qa_synthesizer"
  ];

  routingProfile = id: targets: {
    inherit id;
    default_target = targets.fallback;
    callable_targets = builtins.listToAttrs (
      map (role: {
        name = agents.${role}.id;
        value = targets.${role};
      }) roles
    );
  };

  mixedTargets = {
    coordinator = target "openai-codex" "gpt-5.6-terra" "medium";
    scout = target "opencode-go" "mimo-v2.5" "low";
    planner = target "openai-codex" "gpt-5.6-terra" "medium";
    architect = target "openai-codex" "gpt-5.6-terra" "high";
    implementer = target "opencode-go" "qwen3.7-plus" "medium";
    tester = target "opencode-go" "deepseek-v4-flash" "medium";
    verifier = target "openai-codex" "gpt-5.6-terra" "high";
    critic = target "openai-codex" "gpt-5.6-terra" "high";
    finalizer = target "opencode-go" "qwen3.7-plus" "medium";
    qa_synthesizer = target "openai-codex" "gpt-5.6-terra" "high";
    fallback = target "opencode-go" "qwen3.7-plus" "medium";
  };

  openaiApiTargets = {
    coordinator = target "openai-api" "gpt-5.6-terra" "medium";
    scout = target "openai-api" "gpt-5.6-luna" "low";
    planner = target "openai-api" "gpt-5.6-terra" "medium";
    architect = target "openai-api" "gpt-5.6-terra" "high";
    implementer = target "openai-api" "gpt-5.6-sol" "medium";
    tester = target "openai-api" "gpt-5.6-luna" "medium";
    verifier = target "openai-api" "gpt-5.6-terra" "high";
    critic = target "openai-api" "gpt-5.6-terra" "high";
    finalizer = target "openai-api" "gpt-5.6-sol" "medium";
    qa_synthesizer = target "openai-api" "gpt-5.6-terra" "high";
    fallback = target "openai-api" "gpt-5.6-sol" "medium";
  };

  opencodeGoTargets = {
    coordinator = target "opencode-go" "gpt-5.6-luna" "medium";
    scout = target "opencode-go" "mimo-v2.5" "low";
    planner = target "opencode-go" "qwen3.7-plus" "medium";
    architect = target "opencode-go" "qwen3.7-plus" "high";
    implementer = target "opencode-go" "qwen3.7-plus" "medium";
    tester = target "opencode-go" "mimo-v2.5" "medium";
    verifier = target "opencode-go" "qwen3.7-plus" "high";
    critic = target "opencode-go" "deepseek-v4-flash" "high";
    finalizer = target "opencode-go" "qwen3.7-plus" "medium";
    qa_synthesizer = target "opencode-go" "qwen3.7-plus" "high";
    fallback = target "opencode-go" "qwen3.7-plus" "medium";
  };

  chatgptPlusTargets = {
    coordinator = target "openai-codex" "gpt-5.6-terra" "medium";
    scout = target "openai-codex" "gpt-5.6-luna" "low";
    planner = target "openai-codex" "gpt-5.6-terra" "medium";
    architect = target "openai-codex" "gpt-5.6-terra" "high";
    implementer = target "openai-codex" "gpt-5.6-sol" "medium";
    tester = target "openai-codex" "gpt-5.6-luna" "medium";
    verifier = target "openai-codex" "gpt-5.6-terra" "high";
    critic = target "openai-codex" "gpt-5.6-terra" "high";
    finalizer = target "openai-codex" "gpt-5.6-sol" "medium";
    qa_synthesizer = target "openai-codex" "gpt-5.6-terra" "high";
    fallback = target "openai-codex" "gpt-5.6-sol" "medium";
  };

  freeTarget = target "opencode-zen" "mimo-v2.5-free" "medium";
  freeTargets = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = freeTarget;
    }) (roles ++ [ "fallback" ])
  );
in
{
  agents = builtins.attrValues agents;
  inherit workflows;
  routing_profiles = [
    (routingProfile "router.mixed" mixedTargets)
    (routingProfile "router.openai-api" openaiApiTargets)
    (routingProfile "router.opencode-go" opencodeGoTargets)
    (routingProfile "router.chatgpt-plus" chatgptPlusTargets)
    (routingProfile "router.free" freeTargets)
  ];
}
