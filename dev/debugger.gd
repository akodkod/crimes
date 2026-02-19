class_name Debugger

static func draw_ray_and_collision(
		query: PhysicsRayQueryParameters3D,
		collision: Dictionary,
		duration: float = 1.0,
		show_normal: bool = false,
) -> void:
	if collision:
		var collision_point: Vector3
		var collision_normal: Vector3

		if collision.has("position"):
			collision_point = collision.position
		else:
			push_warning("Collision dictionary missing \"position\" key.")
			return

		if collision.has("normal"):
			collision_normal = collision.normal
		else:
			push_warning("Collision dictionary missing \"normal\" key.")
			return

		# Ray
		DebugDraw3D.draw_arrow(
			query.from,
			collision_point,
			Color.REBECCA_PURPLE,
			0.05,
			true,
			duration,
		)

		# Collision Point
		DebugDraw3D.draw_sphere(
			collision_point,
			0.05,
			Color.GREEN,
			duration,
		)

		# Normal Vector
		if show_normal:
			DebugDraw3D.draw_arrow(
				collision_point,
				collision_point + collision_normal * 0.5,
				Color.GREEN,
				0.03,
				true,
				duration,
			)
	else:
		# Ray
		DebugDraw3D.draw_arrow(
			query.from,
			query.to,
			Color.REBECCA_PURPLE,
			0.05,
			true,
			duration,
		)

		# End Point
		DebugDraw3D.draw_sphere(
			query.to,
			0.05,
			Color.RED,
			duration,
		)


static func draw_sphere(position: Vector3, radius: float, color: Color, duration: float = 1.0) -> void:
	DebugDraw3D.draw_sphere(position, radius, color, duration)
