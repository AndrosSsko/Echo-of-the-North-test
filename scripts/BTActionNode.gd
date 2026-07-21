extends Node
class_name BTActionNode

enum TaskStatus { SUCCESS, FAILURE, RUNNING }

## Virtual execution method template to be overridden by child task classes
func execute_task(_host: CharacterBody3D, _blackboard: AIBlackboard, _delta: float) -> TaskStatus:
	return TaskStatus.FAILURE
