extends Node
class_name BTActionNode
## Base class for reusable behavior tree leaf tasks. A task is stateless
## about *which* enemy it's running for -- all persistent tracking data lives
## on the AIBlackboard passed in, so a single task script can drive any
## number of CharacterBody3D hosts. Subclasses override execute_task().

enum TaskStatus { RUNNING, SUCCESS, FAILURE }

## Runs one tick of this task for `host`, driven by `blackboard` data.
## Returns FAILURE if this task's entry condition isn't met, RUNNING while
## the task is still in progress, or SUCCESS once it completes.
func execute_task(_host: CharacterBody3D, _blackboard: AIBlackboard, _delta: float) -> TaskStatus:
	return TaskStatus.SUCCESS
