---
name: implementation-guide
description: Generate comprehensive implementation guides for coding tasks instead of writing code directly. Use when the user requests detailed implementation documentation, step-by-step development guides, or when they want to implement features themselves using tools like Cursor. Creates exhaustive guides with background context, architecture decisions, milestones with verification points, and rationale for a "build-it-yourself" workflow.
---

# Implementation Guide Generator

This skill generates detailed implementation guides for coding tasks, designed to help developers implement features themselves rather than receiving completed code. The guides provide deep context, teach underlying concepts, explain architectural decisions, and break work into verifiable milestones.

## When to Use This Skill

Use this skill when:
- User asks for an "implementation guide" or "guide to implement X"
- User wants to implement something themselves using Cursor, Windsurf, or similar tools
- User explicitly mentions wanting detailed documentation instead of code
- User asks for a "tutorial" or "step-by-step guide" for implementing a feature
- Context suggests the user wants to stay connected to the implementation process

## Core Principles

### Educational Depth
Implementation guides should teach, not just instruct. Explain:
- **Why** decisions are made, not just what to do
- Background context about technologies and patterns used
- Tradeoffs between different approaches
- How the feature fits into the larger system

### Verifiable Milestones
Every milestone must include:
- Clear goal statement
- Specific changes required
- Detailed implementation steps
- Concrete verification method (tests, visible behavior, commands to run)
- Common pitfalls to avoid

### Assume Mid-Level Developer
Default to mid-level developer experience unless specified otherwise:
- Explain concepts that might not be familiar
- Don't over-explain basics
- Include enough detail to implement successfully
- Provide links for deeper learning

### Customizable Experience Level
The user can specify experience level:
- **Junior**: More detailed explanations, simpler terminology, more examples
- **Mid-level** (default): Balanced detail, assumes familiarity with common patterns
- **Senior**: Higher-level guidance, focus on architecture and tradeoffs

## Guide Structure

Use the template in `references/template.md` as the foundation. Every implementation guide should include:

1. **Overview**: 2-3 sentence summary of what will be implemented
2. **Background & Context**: System context, technical background, rationale for approach
3. **Architecture & Design Decisions**: High-level architecture, key decisions, alternatives considered
4. **Implementation Milestones**: Step-by-step milestones with verification points
5. **Testing Strategy**: Unit, integration, and manual testing approaches
6. **Deployment Considerations**: Prerequisites, rollout strategy, rollback plan
7. **Edge Cases & Error Handling**: Important edge cases and how to handle them
8. **Performance Considerations**: Performance implications and optimizations
9. **Security Considerations**: Security implications and mitigations
10. **Future Enhancements**: Optional improvements for later
11. **Additional Resources**: Links to relevant documentation

See `references/example-rate-limiting.md` for a complete example.

## Writing Implementation Guides

### Start with Context
Before diving into implementation:
1. Ask clarifying questions about:
   - The specific feature or task to implement
   - Existing codebase context (tech stack, architecture patterns)
   - Constraints or requirements
   - Developer experience level (if not specified, use mid-level)
   
2. Once you understand the task, generate the guide directly

### Writing Style
- Use imperative form: "Add the middleware", not "You should add the middleware"
- Be specific: Include file paths, function names, exact commands
- Include code snippets liberally with explanations
- Explain the "why" behind every significant decision
- Anticipate questions the developer might have

### Milestone Design
Each milestone should:
- Build on previous milestones
- Be completable in 15-60 minutes
- Have clear verification criteria
- Include potential issues section
- Feel like meaningful progress

Break down complex features into 3-7 milestones. Too few milestones and the steps are overwhelming; too many and it feels fragmented.

### Code Snippets
Include code snippets that:
- Show the actual implementation, not pseudocode
- Include comments explaining non-obvious parts
- Are complete enough to be copy-pastable with minor adjustments
- Follow the project's conventions (infer from context)

Don't write complete implementations—show the key parts and explain how to fill in the rest.

### Alternatives and Tradeoffs
Always include:
- **Why this approach?**: Explain the chosen approach's benefits
- **Alternative approaches considered**: List alternatives and why they weren't chosen
- **When alternatives might be better**: Conditions where different approaches make sense

This helps developers make informed decisions if circumstances change during implementation.

## Handling Different Task Types

### Backend Features
Focus on:
- Database schema changes
- API design and endpoints
- Business logic architecture
- Integration points with existing systems
- Migration strategies

### Frontend Components
Focus on:
- Component architecture and composition
- State management approach
- Accessibility requirements
- Responsive design considerations
- Performance (rendering, bundle size)

### Refactoring Tasks
Focus on:
- Current state analysis
- Incremental migration path
- Backward compatibility
- Testing strategy to prevent regressions
- Rollback approach

### Infrastructure/DevOps
Focus on:
- Configuration management
- Deployment pipeline changes
- Monitoring and observability
- Disaster recovery
- Cost implications

### Performance Optimization
Focus on:
- Profiling and measurement
- Specific bottlenecks
- Optimization strategies with benchmarks
- Tradeoffs (complexity vs speed)
- How to validate improvements

## Reference Files

- **template.md**: Complete template structure for implementation guides
- **example-rate-limiting.md**: Full example showing all sections in action

Refer to these files when creating guides to ensure consistency and completeness.

## Examples

### User Request: "I need to add authentication to my API"

Generate a guide covering:
- Authentication strategies (JWT vs sessions vs OAuth)
- Chosen approach with rationale
- Milestones: Setup auth library → Implement login endpoint → Add middleware → Secure existing routes → Add refresh tokens
- Security considerations
- Testing strategy
- Migration path for existing users

### User Request: "Build a real-time notification system"

Generate a guide covering:
- Real-time technology options (WebSockets, SSE, polling)
- Architecture (pub/sub, message queue, direct connection)
- Milestones: WebSocket server setup → Connection management → Event publishing → Client integration → Persistence → Scaling
- Performance and connection handling
- Fallback strategies

### User Request: "Refactor our monolith to use microservices"

Generate a guide covering:
- Current monolith analysis
- Service boundary identification
- Incremental extraction strategy
- Milestones: Identify first service → Extract with dual-write → Data migration → Switch traffic → Remove from monolith
- Inter-service communication
- Transaction handling
- Monitoring and debugging distributed system