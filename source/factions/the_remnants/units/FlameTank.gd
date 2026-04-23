extends ResourceGatherer

var resource = 0
var resources_max = null
var resources_gather_rate = null
var harvest_without_dropoff: bool = true


func is_full():
	assert(resource <= resources_max, "flame tank capacity was exceeded somehow")
	return resource == resources_max
