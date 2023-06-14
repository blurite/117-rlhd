package rs117.hd.model;

import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import org.lwjgl.system.MemoryUtil;

public class BufferPool
{
	private static final int SMALLEST_BUCKET_SIZE_BYTES = faceToBytes(512);

	private final long maxCapacity;

	private final List<Long> allHandles = new ArrayList<>();
	private long allBytes; // bytes allocated by the pool

	private final Deque<Long>[] handles = new Deque[]{
		new ArrayDeque<>(), // 512 faces
		new ArrayDeque<>(), // 1024 faces
		new ArrayDeque<>(), // 2048 faces
		new ArrayDeque<>(), // 4096 faces
		new ArrayDeque<>(), // 8192 faces
	};
	private long usedBytes; // bytes handed out by the pool

	private static int faceToBytes(int faces)
	{
		return faces * ModelPusher.DATUM_PER_FACE * ModelPusher.BYTES_PER_DATUM;
	}

	public BufferPool(long byteCapacity)
	{
		this.maxCapacity = byteCapacity;
	}

	private boolean isOverCapacity()
	{
		return allBytes > maxCapacity;
	}

	public void freeAllocations()
	{
		for (long l : allHandles)
		{
			MemoryUtil.nmemFree(l);
		}
		allHandles.clear();
		allBytes = 0;

		for (Deque<Long> handle : handles)
		{
			handle.clear();
		}
		usedBytes = 0;
	}

	private Deque<Long> dequeForSize(int size /* bytes */)
	{
		for (int idx = 0, bucketSize = SMALLEST_BUCKET_SIZE_BYTES; idx < handles.length; ++idx, bucketSize <<= 1)
		{
			if (size <= bucketSize)
			{
				return handles[idx];
			}
		}
		throw new IllegalArgumentException();
	}

	private int /* bytes */ bucketSize(int size /* bytes */)
	{
		for (int bucketSize = SMALLEST_BUCKET_SIZE_BYTES; ; bucketSize <<= 1)
		{
			if (size <= bucketSize)
			{
				return bucketSize;
			}
		}
	}

	private long popChunk(int size /* bytes */)
	{
		Deque<Long> handles = dequeForSize(size);
		if (handles.isEmpty())
		{
			if (isOverCapacity())
			{
				return 0L;
			}

			int bucketSize = bucketSize(size);
			long ptr = MemoryUtil.nmemAllocChecked(bucketSize);
			if (ptr == 0L)
			{
				return 0L;
			}

			allHandles.add(ptr);
			allBytes += bucketSize;

			usedBytes += bucketSize;
			return ptr;
		}

		usedBytes += bucketSize(size);
		return handles.pop();
	}

	private void pushChunk(long ptr, int size /* bytes */)
	{
		assert ptr != 0;

		usedBytes -= bucketSize(size);
		assert usedBytes >= 0L;

		Deque<Long> handles = dequeForSize(size);
		handles.push(ptr);
	}

	public void putIntBuffer(IntBuffer buffer)
	{
		int size = buffer.capacity() * ModelPusher.BYTES_PER_DATUM;
		pushChunk(MemoryUtil.memAddress(buffer), size);
	}

	public IntBuffer takeIntBuffer(int capacity /* int */)
	{
		int size = capacity * ModelPusher.BYTES_PER_DATUM;
		long ptr = popChunk(size);
		if (ptr == 0L)
		{
			return null;
		}

		return MemoryUtil.memIntBuffer(ptr, capacity);
	}

	public void putFloatBuffer(FloatBuffer buffer)
	{
		int size = buffer.capacity() * ModelPusher.BYTES_PER_DATUM;
		pushChunk(MemoryUtil.memAddress(buffer), size);
	}

	public FloatBuffer takeFloatBuffer(int capacity /* float */)
	{
		int size = capacity * ModelPusher.BYTES_PER_DATUM;
		long ptr = popChunk(size);
		if (ptr == 0L)
		{
			return null;
		}

		return MemoryUtil.memFloatBuffer(ptr, capacity);
	}
}
