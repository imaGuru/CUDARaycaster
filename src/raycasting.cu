#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <thrust/sort.h>
#include <thrust/device_ptr.h>

#include "raycasting.h"

#define ALIGN 4
////////////////////////////////////////////////////////////////////////////////
// Helper functions
////////////////////////////////////////////////////////////////////////////////
float Max(float x, float y) {
	return (x > y) ? x : y;
}

float Min(float x, float y) {
	return (x < y) ? x : y;
}

int iDivUp(int a, int b) {
	return ((a % b) != 0) ? (a / b + 1) : (a / b);
}

__device__ TColor make_color(float r, float g, float b, float a) {
	return ((int) (a * 255.0f) << 24) | ((int) (b * 255.0f) << 16)
			| ((int) (g * 255.0f) << 8) | ((int) (r * 255.0f) << 0);
}

////////////////////////////////////////////////////////////////////////////////
// Global data handlers and parameters
////////////////////////////////////////////////////////////////////////////////
//Texture reference and channel descriptor for image texture
texture<uchar4, 2, cudaReadModeNormalizedFloat> texImage;
cudaChannelFormatDesc uchar4tex = cudaCreateChannelDesc<uchar4>();

//CUDA array descriptor
cudaArray *a_Src;

#include "utility.cuh"
////////////////////////////////////////////////////////////////////////////////
// Vector2
////////////////////////////////////////////////////////////////////////////////
CUDA_CALLABLE_MEMBER const Vector2 Vector2::operator*(const float &q) const {
	return (Vector2(this->x * q, this->y * q));
}

CUDA_CALLABLE_MEMBER const Vector2 Vector2::operator/(const float &q) const {
	return (Vector2(this->x / q, this->y / q));
}

CUDA_CALLABLE_MEMBER const Vector2 Vector2::operator+(const Vector2& q) const {
	return (Vector2(this->x + q.x, this->y + q.y));
}

CUDA_CALLABLE_MEMBER const Vector2 Vector2::operator-(const Vector2& q) const {
	return (Vector2(x - q.x, y - q.y));
}

CUDA_CALLABLE_MEMBER const Vector2 Vector2::direction() const {
	float length = sqrtf((this->x * this->x) + (this->y * this->y));
	return Vector2(this->x / length, this->y / length);
}
CUDA_CALLABLE_MEMBER float Vector2::length() const {
	return sqrtf((this->x * this->x) + (this->y * this->y));
}

////////////////////////////////////////////////////////////////////////////////
// Vector3
////////////////////////////////////////////////////////////////////////////////

CUDA_CALLABLE_MEMBER const Vector3 Vector3::operator*(const float q) const {
	return (Vector3(this->x * q, this->y * q, this->z * q));
}

CUDA_CALLABLE_MEMBER const Vector3 Vector3::operator/(const float &q) const {
	return (Vector3(this->x / q, this->y / q, this->z / q));
}

CUDA_CALLABLE_MEMBER const Vector3 Vector3::operator+(const Vector3& q) const {
	return (Vector3(this->x + q.x, this->y + q.y, this->z + q.z));
}

CUDA_CALLABLE_MEMBER const Vector3 Vector3::operator-(const Vector3& q) const {
	return (Vector3(this->x - q.x, this->y - q.y, this->z - q.z));
}
CUDA_CALLABLE_MEMBER const Vector3 Vector3::operator-() const {
	return Vector3(-(this->x), -(this->y), -(this->z));
}

CUDA_CALLABLE_MEMBER const Vector3 Vector3::direction() const {
	float length = sqrtf(
			(this->x * this->x) + (this->y * this->y) + (this->z * this->z));
	return Vector3(this->x / length, this->y / length, this->z / length);
}

CUDA_CALLABLE_MEMBER float Vector3::dot(const Vector3& q) const {
	return this->x * q.x + this->y * q.y + this->z * q.z;
}

CUDA_CALLABLE_MEMBER const Vector3 Vector3::cross(const Vector3& q) const {
	return Vector3(this->y * q.z - this->z * q.y, this->z * q.x - this->x * q.z,
			this->x * q.y - this->y * q.x);
}

CUDA_CALLABLE_MEMBER float Vector3::length() const {
	return sqrtf(
			(this->x * this->x) + (this->y * this->y) + (this->z * this->z));
}

////////////////////////////////////////////////////////////////////////////////
// Ray
////////////////////////////////////////////////////////////////////////////////

CUDA_CALLABLE_MEMBER const Vector3& Ray::origin() const {
	return m_origin;
}
CUDA_CALLABLE_MEMBER const Vector3& Ray::direction() const {
	return m_direction;
}

////////////////////////////////////////////////////////////////////////////////
// Triangle
////////////////////////////////////////////////////////////////////////////////
CUDA_CALLABLE_MEMBER const Vector3& Triangle::vertex(int i) const {
	return m_vertex[i];
}

CUDA_CALLABLE_MEMBER const Vector3& Triangle::normal(int i) const {
	return m_normal[i];
}

CUDA_CALLABLE_MEMBER const BSDF& Triangle::bsdf() const {
	return m_bsdf;
}
////////////////////////////////////////////////////////////////////////////////
// Color3
////////////////////////////////////////////////////////////////////////////////
CUDA_CALLABLE_MEMBER const Color3 Color3::operator*(const float &q) const {
	return Color3(this->r * q, this->g * q, this->b * q);
}

CUDA_CALLABLE_MEMBER const Color3 Color3::operator*(const Color3 &q) const {
	return Color3(this->r * q.r, this->g * q.g, this->b * q.b);
}

CUDA_CALLABLE_MEMBER const Color3 Color3::operator/(const float &q) const {
	return Color3(this->r / q, this->g / q, this->b / q);
}

CUDA_CALLABLE_MEMBER const Color3 Color3::operator+(const Color3 &q) const {
	return Color3(this->r + q.r, this->g + q.g, this->b + q.b);
}

CUDA_CALLABLE_MEMBER Color3 BSDF::evaluateFiniteScatteringDensity(
		const Vector3& w_i, const Vector3& w_o, const Vector3& n) const {
	const Vector3& w_h = (w_i + w_o).direction();
	//return k_L / PI;
	return (k_L + k_G * ((s + 8.0f) * powf(max(0.0f, w_h.dot(n)), s) / 8.0f))
			/ PI;
}

CUDA_CALLABLE_MEMBER Ray Camera::computeEyeRay(float x, float y, int width,
		int height) {
	const float aspect = float(height) / width;

	const float s = fieldOfView;
	Vector3 image_point = right * (x / width - 0.5f) * s
			+ up * (y / height - 0.5f) * aspect * s + position + direction;
	Vector3 ray_direction = image_point - position;
	return Ray(position, ray_direction.direction());
}

CUDA_CALLABLE_MEMBER void Camera::setPosition(const Vector3& position) {
	this->position = position;
}
CUDA_CALLABLE_MEMBER void Camera::lookAt(const Vector3& point,
		const Vector3& up) {
	direction = (point - position).direction();
	right = direction.cross(up).direction();
	this->up = right.cross(direction).direction();
}

CUDA_CALLABLE_MEMBER Vector3 AABoundingBox::getCenter() const {
	return Vector3((maxX + minX) * 0.5f, (maxY + minY) * 0.5f,
			(maxZ + minZ) * 0.5f);
}

CUDA_CALLABLE_MEMBER const AABoundingBox AABoundingBox::operator+(
		const AABoundingBox &q) const {
	return AABoundingBox(min(this->minX, q.minX), min(this->minY, q.minY),
			min(this->minZ, q.minZ), max(this->maxX, q.maxX),
			max(this->maxY, q.maxY), max(this->maxZ, q.maxZ));
}
////////////////////////////////////////////////////////////////////////////////
// BVH creation
////////////////////////////////////////////////////////////////////////////////
// Expands a 10-bit integer into 30 bits
// by inserting 2 zeros after each bit.
__device__ unsigned int expandBits(unsigned int v) {
	v = (v * 0x00010001u) & 0xFF0000FFu;
	v = (v * 0x00000101u) & 0x0F00F00Fu;
	v = (v * 0x00000011u) & 0xC30C30C3u;
	v = (v * 0x00000005u) & 0x49249249u;
	return v;
}

// Calculates a 30-bit Morton code for the
// given 3D point located within the unit cube [0,1].
__device__ unsigned int morton3D(float x, float y, float z) {
	x = min(max(x * 1024.0f, 0.0f), 1023.0f);
	y = min(max(y * 1024.0f, 0.0f), 1023.0f);
	z = min(max(z * 1024.0f, 0.0f), 1023.0f);
	unsigned int xx = expandBits((unsigned int) x);
	unsigned int yy = expandBits((unsigned int) y);
	unsigned int zz = expandBits((unsigned int) z);
	return (xx << 2) + (yy << 1) + zz;
}

__device__ int ones32(unsigned int x) {
	/* 32-bit recursive reduction using SWAR...
	 but first step is mapping 2-bit values
	 into sum of 2 1-bit values in sneaky way
	 */
	x -= ((x >> 1) & 0x55555555);
	x = (((x >> 2) & 0x33333333) + (x & 0x33333333));
	x = (((x >> 4) + x) & 0x0f0f0f0f);
	x += (x >> 8);
	x += (x >> 16);
	return (x & 0x0000003f);
}

__device__ int lzc(unsigned int x) {
	x |= (x >> 1);
	x |= (x >> 2);
	x |= (x >> 4);
	x |= (x >> 8);
	x |= (x >> 16);
	return (32 - ones32(x));
}

__device__ int commonPrefixCount(unsigned int* d_sortedMortonCodes,
		unsigned int i, unsigned int j) {
	if (d_sortedMortonCodes[i] == d_sortedMortonCodes[j])
		return lzc(i ^ j); //this is probably wrong, fix
	return lzc(d_sortedMortonCodes[i] ^ d_sortedMortonCodes[j]);
}

__device__ int2 determineRange(unsigned int* d_sortedMortonCodes,
		unsigned int objCount, int i) {
	int dir, minDist;
	if (i == 0) {
		dir = 1;
		minDist = -1;
	} else {
		dir = commonPrefixCount(d_sortedMortonCodes, i, i + 1)
				- commonPrefixCount(d_sortedMortonCodes, i, i - 1);
		dir = dir < 0 ? -1 : 1;
		minDist = commonPrefixCount(d_sortedMortonCodes, i, i - dir);
	}
	int2 range;

	int step = 2;
	while (1) {
		int newPos = (int) i + dir * step;
		if (newPos < objCount && newPos >= 0
				&& commonPrefixCount(d_sortedMortonCodes, i, newPos) > minDist)
			step = step << 1; // exponential increase
		else
			break;
	}

	int start = i;
	do {
		step = (step + 1) >> 1; // exponential decrease
		int newStart = start + step * dir; // proposed new position
		if (newStart < objCount && newStart >= 0
				&& commonPrefixCount(d_sortedMortonCodes, i, newStart)
						> minDist)
			start = newStart; // accept proposal
	} while (step > 1);

	if (start < i) {
		range.x = start;
		range.y = i;
	} else {
		range.x = i;
		range.y = start;
	}
	return range;
}

__device__ int findSplit(unsigned int* sortedMortonCodes, int first, int last) {
	unsigned int firstCode = sortedMortonCodes[first];
	unsigned int lastCode = sortedMortonCodes[last];

	// Identical Morton codes => split the range in the middle.
	if (firstCode == lastCode)
		return (first + last) >> 1;

	// Calculate the number of highest bits that are the same
	int commonPrefix = commonPrefixCount(sortedMortonCodes, first, last);

	// Use binary search to find where the next bit differs.
	// Specifically, we are looking for the highest object that
	// shares more than commonPrefix bits with the first one.
	int split = first; // initial guess
	int step = last - first;

	do {
		step = (step + 1) >> 1; // exponential decrease
		int newSplit = split + step; // proposed new position

		if (newSplit < last
				&& commonPrefixCount(sortedMortonCodes, first, newSplit)
						> commonPrefix)
			split = newSplit; // accept proposal
	} while (step > 1);

	return split;
}
////////////////////////////////////////////////////////////////////////////////
// Raycasting device functions
////////////////////////////////////////////////////////////////////////////////
__device__ bool rayAABBIntersect(Ray r, AABoundingBox aabb) {
	Vector3 dirfrac;
	dirfrac.x = 1.0f / r.direction().x;
	dirfrac.y = 1.0f / r.direction().y;
	dirfrac.z = 1.0f / r.direction().z;
	// lb is the corner of AABB with minimal coordinates - left bottom, rt is maximal corner
	// r.org is origin of ray
	float t1 = (aabb.minX - r.origin().x) * dirfrac.x;
	float t2 = (aabb.maxX - r.origin().x) * dirfrac.x;
	float t3 = (aabb.minY - r.origin().y) * dirfrac.y;
	float t4 = (aabb.maxY - r.origin().y) * dirfrac.y;
	float t5 = (aabb.minZ - r.origin().z) * dirfrac.z;
	float t6 = (aabb.maxZ - r.origin().z) * dirfrac.z;

	float tmin = max(max(min(t1, t2), min(t3, t4)), min(t5, t6));
	float tmax = min(min(max(t1, t2), max(t3, t4)), max(t5, t6));

	// if tmax < 0, ray (line) is intersecting AABB, but whole AABB is behing us
	if (tmax < 0) {
		return false;
	}

	// if tmin > tmax, ray doesn't intersect AABB
	if (tmin > tmax) {
		return false;
	}
	return true;
}
__device__ float intersect(const Ray& R, const Triangle& T, float weight[3]) {
	const Vector3& e1 = T.vertex(1) - T.vertex(0);
	const Vector3& e2 = T.vertex(2) - T.vertex(0);
	const Vector3& q = R.direction().cross(e2);

	const float a = e1.dot(q);
	const Vector3& s = R.origin() - T.vertex(0);
	const Vector3& r = s.cross(e1);

	// Barycentric vertex weights
	weight[1] = s.dot(q) / a;
	weight[2] = R.direction().dot(r) / a;
	weight[0] = 1.0f - (weight[1] + weight[2]);
	const float dist = e2.dot(r) / a;
	const float epsilon = 1e-7f;

	const float epsilon2 = 1e-10f;

	if ((a <= epsilon) || (weight[0] < -epsilon2) || (weight[1] < -epsilon2)
			|| (weight[2] < -epsilon2) || (dist <= 0.0f)) {
		// The ray is nearly parallel to the triangle, or the
		// intersection lies outside the triangle or behind
		// the ray origin: "infinite" distance until intersection.
		return INFINITY;
	} else {
		return dist;
	}
}
__device__ void shade(const Triangle& T, const Vector3& P, const Vector3& n,
		const Vector3& w_o, Radiance3& L_o, Light& light) {

	const Vector3& offset = light.position - P;
	const float distanceToLight = offset.length();
	//Normalize the offset vector
	const Vector3& w_i = offset / distanceToLight;

	// Scatter the light
	L_o = (light.power / (distanceToLight * distanceToLight))
			* T.bsdf().evaluateFiniteScatteringDensity(w_i, w_o, n)
			* max(0.0, w_i.dot(n));
}

__device__ bool sampleRayTriangle(const Ray& R, const Triangle& T,
		Radiance3& radiance, float& distance, Light& light) {
	float weight[3];
	const float d = intersect(R, T, weight);
	if (d >= distance) {
		return false;
	}
	distance = d;
	// This intersection is closer than the previous one
	// Intersection point
	const Vector3& P = R.origin() + R.direction() * d;
	// Find the interpolated vertex normal at the intersection
	const Vector3& n = (T.normal(0) * weight[0] + T.normal(1) * weight[1]
			+ T.normal(2) * weight[2]).direction();
	const Vector3& w_o = -R.direction();

	shade(T, P, n, w_o, radiance, light);

	// Debugging barycentric
	// radiance = Radiance3(weight[0], weight[1], weight[2])*0.14f;

	return true;
}
__device__ Vector3 getVector(unsigned int i, float* data) {
	return Vector3(data[i], data[i + 1], data[i + 2]);
}

////////////////////////////////////////////////////////////////////////////////
// kernels
////////////////////////////////////////////////////////////////////////////////

__global__ void calculateLeafAABBs(unsigned int objCount, unsigned int* d_faces,
		float* d_vertices, unsigned int* d_objectIds, AABoundingBox* d_aabbs) {
	const unsigned int idx = threadIdx.x + blockIdx.x * blockDim.x;
	if (idx < objCount) {
		AABoundingBox aabb(getVector((d_faces[idx * 6] - 1) * 3, d_vertices),
				getVector((d_faces[idx * 6 + 1] - 1) * 3, d_vertices),
				getVector((d_faces[idx * 6 + 2] - 1) * 3, d_vertices));
		d_objectIds[idx] = idx;
		d_aabbs[idx] = aabb;
	}
}

__global__ void assignMortonCodes(unsigned int* d_mortonCodes,
		AABoundingBox* d_aabbs, unsigned int objCount, Vector3 sceneMin,
		Vector3 sceneMax) {
	const unsigned int idx = threadIdx.x + blockIdx.x * blockDim.x;
	if (idx < objCount) {

		const Vector3& relativeCenter = d_aabbs[idx].getCenter() - sceneMin;
		const Vector3& sceneSize = sceneMax - sceneMin;
		d_mortonCodes[idx] = morton3D(relativeCenter.x / sceneSize.x,
				relativeCenter.y / sceneSize.y, relativeCenter.z / sceneSize.z);
	}
}

__global__ void calculateTreeAABBs(BVHNode* d_bvhNodes, unsigned int objCount) {
	const unsigned int idx = threadIdx.x + blockIdx.x * blockDim.x;
	if (idx < objCount) {
		BVHNode* current = &d_bvhNodes[d_bvhNodes[idx + objCount - 1].parent];
		while (1) {
			int old = atomicAdd(&(current->visited), 1);
			if (old == 0) {
				break;
			}
			current->aabb = d_bvhNodes[current->left].aabb
					+ d_bvhNodes[current->right].aabb;
			if (current->parent == -1)
				break;
			current = &d_bvhNodes[current->parent];

		}
	}
}

__global__ void createHierarchy(unsigned int* d_sortedObjectIds,
		unsigned int* d_sortedMortonCodes, AABoundingBox* d_aabbs,
		unsigned int objCount, BVHNode* d_bvhNodes) {
	const unsigned int idx = threadIdx.x + blockDim.x * blockIdx.x;
	if (idx < objCount) {
		unsigned int id = d_sortedObjectIds[idx];
		d_bvhNodes[idx + objCount - 1].aabb = d_aabbs[id];
		d_bvhNodes[idx + objCount - 1].objectId = id;
		d_bvhNodes[idx + objCount - 1].isLeaf = true;
	}
	// Construct internal nodes.
	if (idx < objCount - 1) {

		// Find out which range of objects the node corresponds to.
		int2 range = determineRange(d_sortedMortonCodes, objCount, idx);
		int first = range.x;
		int last = range.y;

		// Determine where to split the range.
		int split = findSplit(d_sortedMortonCodes, first, last);
		unsigned int left;
		if (split == first)
			left = split + objCount - 1;
		else
			left = split;

		unsigned int right;
		if (split + 1 == last)
			right = split + 1 + objCount - 1;
		else
			right = split + 1;

		d_bvhNodes[idx].left = left;
		d_bvhNodes[idx].right = right;
		d_bvhNodes[idx].isLeaf = false;
		d_bvhNodes[idx].visited = 0;
		if (idx == 0)
			d_bvhNodes[idx].parent = -1;
		d_bvhNodes[left].parent = idx;
		d_bvhNodes[right].parent = idx;

	}
}

__global__ void rayCast(TColor *dst, int imageW, int imageH, Camera camera,
		Light light, unsigned int faceCount, unsigned int vertexCount,
		unsigned int normalCount, unsigned int* d_faces, float* d_vertices,
		float*d_normals, BVHNode* d_bvhNodes) {

	//Global x, y image coordinates
	const unsigned int ix = blockDim.x * blockIdx.x + threadIdx.x;
	const unsigned int iy = blockDim.y * blockIdx.y + threadIdx.y;

	if (ix < imageW && iy < imageH) {
		Triangle triangle;
		//Color of our pixel
		Radiance3 L_o(0.08f, 0.08f, 0.08f);
		const Ray& ray = camera.computeEyeRay(ix + 0.5f, iy + 0.5f, imageW,
				imageH);
		//Now find the closest triangle that intersects with our ray
		float distance = INFINITY;

		int triangles[8];
		int triangleCount = 0;
		int stack[32];
		int stackIdx = 0;
		stack[stackIdx++] = 0; // index to the first BVH node
		while (stackIdx) {
			BVHNode* current = &d_bvhNodes[stack[stackIdx - 1]];
			stackIdx--;
			if (rayAABBIntersect(ray, current->aabb)) {
				if (!current->isLeaf) {
					// Internal node
					stack[stackIdx++] = current->left;
					stack[stackIdx++] = current->right;
				} else {
					// Leaf node
					triangles[triangleCount++] = current->objectId;
				}
			}
		}

		for (int i = 0; i < triangleCount; i++) {
			triangle.load(
					getVector((d_faces[triangles[i] * 6] - 1) * 3, d_vertices),
					getVector((d_faces[triangles[i] * 6 + 1] - 1) * 3,
							d_vertices),
					getVector((d_faces[triangles[i] * 6 + 2] - 1) * 3,
							d_vertices),
					getVector((d_faces[triangles[i] * 6 + 3] - 1) * 3,
							d_normals),
					getVector((d_faces[triangles[i] * 6 + 4] - 1) * 3,
							d_normals),
					getVector((d_faces[triangles[i] * 6 + 5] - 1) * 3,
							d_normals),
					BSDF(Color3(0.4f, 0.8f, 0.2f), Color3(0.2f, 0.2f, 0.2f),
							80.0f));
			sampleRayTriangle(ray, triangle, L_o, distance, light);
		}
		dst[imageW * iy + ix] = make_color(min(L_o.r, 1.0f), min(L_o.g, 1.0f),
				min(L_o.b, 1.0f), 1.0);
	}
}

////////////////////////////////////////////////////////////////////////////////
// CUDA code handles
////////////////////////////////////////////////////////////////////////////////
extern "C" cudaError_t CUDA_Bind2TextureArray() {
	return cudaBindTextureToArray(texImage, a_Src);
}

extern "C" cudaError_t CUDA_UnbindTexture() {
	return cudaUnbindTexture(texImage);
}

extern "C" cudaError_t CUDA_MallocArray(uchar4 **h_Src, int imageW,
		int imageH) {
	cudaError_t error;

	error = cudaMallocArray(&a_Src, &uchar4tex, imageW, imageH);
	error = cudaMemcpyToArray(a_Src, 0, 0, *h_Src,
			imageW * imageH * sizeof(uchar4), cudaMemcpyHostToDevice);

	return error;
}

extern "C" cudaError_t CUDA_FreeArray() {
	return cudaFreeArray(a_Src);
}

extern "C" void cuda_rayCasting(TColor *d_dst, int imageW, int imageH,
		Camera camera, Light light, unsigned int faceCount,
		unsigned int vertexCount, unsigned int normalCount,
		unsigned int* d_faces, float* d_vertices, float*d_normals,
		unsigned int* d_objectIds, unsigned int* d_mortonCodes,
		AABoundingBox* d_aabbs, BVHNode* d_bvhNodes, AABoundingBox* h_aabbs) {
	dim3 threads(BLOCKDIM_X, BLOCKDIM_Y);
	dim3 grid(iDivUp(imageW, BLOCKDIM_X), iDivUp(imageH, BLOCKDIM_Y));

	//Calculate AABBs and morton codes for leaf nodes
	//printf("%d\n", faceCount);
	calculateLeafAABBs<<<faceCount / 512 + 1, 512>>>(faceCount, d_faces,
			d_vertices, d_objectIds, d_aabbs);
	cudaMemcpy(h_aabbs, d_aabbs, faceCount * sizeof(AABoundingBox),
			cudaMemcpyDeviceToHost);
	Vector3 sceneMin(INFINITY, INFINITY, INFINITY), sceneMax(-INFINITY,
			-INFINITY, -INFINITY);
	for (int i = 0; i < faceCount; i++) {
		AABoundingBox aabb = h_aabbs[i];
		if (aabb.minX < sceneMin.x)
			sceneMin.x = aabb.minX;
		if (aabb.minY < sceneMin.y)
			sceneMin.y = aabb.minY;
		if (aabb.minZ < sceneMin.z)
			sceneMin.z = aabb.minZ;

		if (aabb.maxX > sceneMax.x)
			sceneMax.x = aabb.maxX;
		if (aabb.maxY > sceneMax.y)
			sceneMax.y = aabb.maxY;
		if (aabb.maxZ > sceneMax.z)
			sceneMax.z = aabb.maxZ;
	}
	assignMortonCodes<<<faceCount / 512 + 1, 512>>>(d_mortonCodes, d_aabbs,
			faceCount, sceneMin, sceneMax);
	cudaDeviceSynchronize();
	//Sort objects by morton codes
	thrust::device_ptr<unsigned int> d_data_ptr(d_objectIds);
	thrust::device_ptr<unsigned int> d_keys_ptr(d_mortonCodes);
	thrust::sort_by_key(d_keys_ptr, d_keys_ptr + faceCount, d_data_ptr);
	d_mortonCodes = thrust::raw_pointer_cast(d_keys_ptr);
	d_objectIds = thrust::raw_pointer_cast(d_data_ptr);
	createHierarchy<<<faceCount / 512 + 1, 512>>>(d_objectIds, d_mortonCodes,
			d_aabbs, faceCount, d_bvhNodes);
	cudaDeviceSynchronize();
	//Calculate bounding boxes for internal nodes
	calculateTreeAABBs<<<faceCount / 512 + 1, 512>>>(d_bvhNodes, faceCount);
	cudaDeviceSynchronize();
	//Raycast
	rayCast<<<grid, threads>>>(d_dst, imageW, imageH, camera, light, faceCount,
			vertexCount, normalCount, d_faces, d_vertices, d_normals,
			d_bvhNodes);
}
