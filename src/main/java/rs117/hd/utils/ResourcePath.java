/*
 * Copyright (c) 2022, Hooder <ahooder@protonmail.com>
 * Copyright (c) 2022, Mark <https://github.com/Mark7625>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
package rs117.hd.utils;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import lombok.NonNull;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;
import org.lwjgl.BufferUtils;
import org.lwjgl.system.MemoryUtil;
import org.lwjgl.system.Platform;

import javax.annotation.Nullable;
import javax.annotation.RegEx;
import java.io.*;
import java.net.URL;
import java.nio.ByteBuffer;
import java.nio.channels.Channels;
import java.nio.channels.ReadableByteChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Stack;
import java.util.function.BiFunction;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.stream.Collectors;

@Slf4j
public class ResourcePath {
    // This could probably be improved to extract the source set from toURL()
    @Setter
    private static String RESOURCE_DIR = "src/main/resources";

    private static final Gson GSON = new GsonBuilder().setLenient().create();
    private static final FileWatcher.UnregisterCallback NOOP = () -> {};

    @Nullable
    public final ResourcePath root;
    @Nullable
    public final String path;

    public static ResourcePath path(Path path) {
        return path(path.toString());
    }

    public static ResourcePath path(String... parts) {
        return new ResourcePath(parts);
    }

    public static ResourcePath path(Class<?> root, String... parts) {
        return new ClassResourcePath(root, parts);
    }

    public static ResourcePath path(ClassLoader root, String... parts)  {
        return new ClassLoaderResourcePath(root, parts);
    }

    private ResourcePath(String... parts) {
        this(null, parts);
    }

    private ResourcePath(ResourcePath root) {
        this.root = root;
        this.path = null;
    }

    private ResourcePath(ResourcePath root, String... parts) {
        this.root = root;
        this.path = normalize(parts);
    }

    public ResourcePath chroot() {
        return new ResourcePath(this);
    }

    public ResourcePath resolve(String... parts) {
        return new ResourcePath(root, normalize(path, parts));
    }

    public String getFilename() {
        if (path == null)
            return "";
        int i = path.lastIndexOf("/");
        if (i != -1)
            return path.substring(i + 1);
        return path;
    }

    public String getExtension() {
        return getExtension(0);
    }

    public String getExtension(int nthLast) {
        String filename = getFilename();
        String extension = "";
        while (nthLast-- >= 0) {
            int i = filename.lastIndexOf('.');
            if (i == -1)
                return nthLast >= 0 ? "" : filename;
            extension = filename.substring(i + 1);
            filename = filename.substring(0, i);
        }
        return extension;
    }

    public ResourcePath setExtension(String extension) {
        if (path == null)
            throw new IllegalStateException("Cannot set extension for root path: " + this);

        String path = this.path;
        int i = path.lastIndexOf('.');
        if (i != -1)
            path = path.substring(0, i);
        return new ResourcePath(root, path);
    }

    public boolean matches(@RegEx String posixPathRegex) {
        return toPosixPath().matches(posixPathRegex);
    }

    @Override
    public String toString() {
        String path = toPosixPath();
        return path.length() == 0 ? "." : path;
    }

    public ResourcePath toAbsolute() {
        if (root != null) {
            Path rootPath = root.toPath().toAbsolutePath();
            Path path = toPath().toAbsolutePath();
            return new ResourcePath(root, rootPath.relativize(path).toString());
        }
        return path(toPath().toAbsolutePath());
    }

    public String toPosixPath() {
        if (root != null)
            return normalize(root.toPosixPath(), new String[] { path });
        return path;
    }

    public Path toPath() {
        if (root == null) {
            assert path != null;
            return Paths.get(path);
        }

        Path basePath = root.toPath();
        if (path == null)
            return basePath;

        String relativePath = path.startsWith("/") ? path.substring(1) : path;
        return basePath.resolve(relativePath);
    }

    public Path toRealPath() {
        try {
            return toPath().toRealPath();
        } catch (IOException ex) {
            throw new RuntimeException("Failed to resolve real path for resource: " + this, ex);
        }
    }

    @NonNull
    public URL toURL() {
        try {
            if (root == null)
                return new URL("file:" + toRealPath());
            URL rootURL = root.toURL();
            return new URL(rootURL, rootURL.getProtocol() + ":" + normalize(rootURL.getPath(), new String[] { path }));
        } catch (IOException ex) {
            throw new RuntimeException("Failed to resolve resource: " + this, ex);
        }
    }

    public BufferedReader toReader() {
        return new BufferedReader(new InputStreamReader(toInputStream(), StandardCharsets.UTF_8));
    }

    public InputStream toInputStream() {
        if (path == null)
            throw new IllegalStateException("Cannot get InputStream for root path: " + this);

        if (root != null) {
            String path = this.path;
            if (path.startsWith("/"))
                path = path.substring(1);
            return root.resolve(path).toInputStream();
        }

        try {
            return new FileInputStream(path);
        } catch (FileNotFoundException ex) {
            throw new RuntimeException("Unable to load resource: " + this, ex);
        }
    }

    public boolean isClassResource() {
        if (root != null)
            return root.isClassResource();
        return false;
    }

    /**
     * Check if the resource pointed to is actually on the file system, even if it is loaded as a class resource.
     */
    public boolean isFileSystemResource() {
        return toURL().getProtocol().equals("file");
    }

    /**
     * Run the callback once at the start & every time the resource (or sub resource) changes.
     * @param changeHandler Callback to call once at the start and every time the resource changes
     * @return A runnable that can be called to unregister the watch callback
     */
    public FileWatcher.UnregisterCallback watch(Consumer<ResourcePath> changeHandler) {
        // Only watch files on the file system
        if (!isFileSystemResource()) {
            changeHandler.accept(this);
            return NOOP;
        }

        ResourcePath path = this;
        // If the resource is loaded by a class or class loader, attempt to redirect it to the main resource directory
        if (isClassResource()) {
            // Assume the project's resource directory lies at "src/main/resources" in the process working directory
            path = path(RESOURCE_DIR).chroot().resolve(toAbsolute().toPath().toString());
        }

        return FileWatcher.watchPath(path, changeHandler);
    }

    public String loadString() throws IOException {
        try (BufferedReader reader = toReader()) {
            return reader.lines().collect(Collectors.joining(System.lineSeparator()));
        }
    }

    public <T> T loadJson(Class<T> type) throws IOException {
        try (BufferedReader reader = toReader()) {
            return GSON.fromJson(reader, type);
        }
    }

    /**
     * Reads the full InputStream into a garbage-collected ByteBuffer allocated with BufferUtils.
     * @return a ByteBuffer
     * @throws IOException if the InputStream cannot be read
     */
    public ByteBuffer loadByteBuffer() throws IOException {
        return readInputStream(toInputStream(), BufferUtils::createByteBuffer, null);
    }

    /**
     * Reads the full InputStream into a ByteBuffer allocated with malloc, which must be explicitly freed.
     * @return a ByteBuffer
     * @throws IOException if the InputStream cannot be read
     */
    public ByteBuffer loadByteBufferMalloc() throws IOException {
        return readInputStream(toInputStream(), MemoryUtil::memAlloc, MemoryUtil::memRealloc);
    }

    /**
     * Reads the full InputStream into a garbage-collected ByteBuffer allocated with BufferUtils.
     * @param is the InputStream
     * @return a ByteBuffer
     * @throws IOException if the InputStream cannot be read
     */
    private static ByteBuffer readInputStream(
        InputStream is,
        Function<Integer, ByteBuffer> alloc,
        @Nullable BiFunction<ByteBuffer, Integer, ByteBuffer> realloc
    ) throws IOException {
        if (realloc == null) {
            realloc = (ByteBuffer oldBuffer, Integer newSize) -> {
                ByteBuffer newBuffer = alloc.apply(newSize);
                newBuffer.put(oldBuffer);
                return newBuffer;
            };
        }

        try (ReadableByteChannel channel = Channels.newChannel(is)) {
            // Read all currently buffered data into a ByteBuffer
            ByteBuffer buffer = alloc.apply(is.available());
            channel.read(buffer);

            // If there's more data available, double the buffer size and round up to the nearest power of 2
            if (is.available() > buffer.remaining()) {
                int newSize = (buffer.position() + is.available()) * 2;
                int nearestPow2 = 2 << (31 - Integer.numberOfLeadingZeros(newSize - 1));
                buffer = realloc.apply(buffer, nearestPow2);
            }

            // Continue reading all bytes, doubling the buffer each time it runs out of space
            while (is.available() > 0)
                if (buffer.remaining() == channel.read(buffer))
                    buffer = realloc.apply(buffer, buffer.capacity() * 2);

            channel.close();
            return buffer.flip();
        }
    }

    private static String normalizeSlashes(String path) {
        if (Platform.get() == Platform.WINDOWS)
            return path.replace("\\", "/");
        return path;
    }

    private static String normalize(String... parts) {
        return normalize(null, parts);
    }

    private static String normalize(@Nullable String workingDirectory, String[] parts) {
        Stack<String> resolvedParts = new Stack<>();
        if (workingDirectory != null && workingDirectory.length() > 0 && !workingDirectory.equals("."))
            resolvedParts.addAll(Arrays.asList(normalizeSlashes(workingDirectory).split("/")));

        for (String part : parts) {
            if (part == null || part.length() == 0 || part.equals("."))
                continue;

            part = normalizeSlashes(part);

            if (isAbsolute(part))
                resolvedParts.clear();

            for (String normalizedPart : part.split("/")) {
                if (normalizedPart.equals("..") &&
                        resolvedParts.size() > 0 &&
                        !resolvedParts.peek().equals("..")) {
                    resolvedParts.pop();
                } else {
                    resolvedParts.push(normalizedPart);
                }
            }
        }

        return String.join("/", resolvedParts);
    }

    /**
     * Expects forward slashes as path delimiter, but accepts Windows-style drive letter prefixes.
     */
    private static boolean isAbsolute(String path) {
        if (Platform.get() == Platform.WINDOWS)
            path = path.replaceFirst("^\\w:", "");
        return path.startsWith("/");
    }

    private static class ClassResourcePath extends ResourcePath {
        public final Class<?> root;

        public ClassResourcePath(@NonNull Class<?> root, String... parts) {
            super(parts);
            this.root = root;
        }

        @Override
        public ResourcePath resolve(String... parts) {
            return new ClassResourcePath(root, normalize(path, parts));
        }

        @Override
        public String toString() {
            return super.toString() + " from class " + root.getName();
        }

        @Override
        public ResourcePath toAbsolute() {
            return path(root, normalize("/" + root.getPackage().getName().replace(".", "/"), path));
        }

        @Override
        public boolean isClassResource() {
            return true;
        }

        @Override
        @NonNull
        public URL toURL() {
            assert path != null;
            URL url = root.getResource(path);
            if (url == null)
                throw new RuntimeException("No resource found for path " + this);
            return url;
        }

        @Override
        public InputStream toInputStream() {
            assert path != null;
            InputStream is = root.getResourceAsStream(path);
            if (is == null)
                throw new RuntimeException("Missing resource: " + this);
            return is;
        }
    }

    private static class ClassLoaderResourcePath extends ResourcePath {
        public final ClassLoader root;

        public ClassLoaderResourcePath(ClassLoader root, String... parts) {
            super(parts);
            this.root = root;
        }

        @Override
        public ResourcePath resolve(String... parts) {
            return new ClassLoaderResourcePath(root, normalize(path, parts));
        }

        @Override
        public String toString() {
            return super.toString() + " from class loader " + root;
        }

        @Override
        public ResourcePath toAbsolute() {
            assert path != null;
            return path.startsWith("/") ? this : path(root, "/", path);
        }

        @Override
        public boolean isClassResource() {
            return true;
        }

        @Override
        @NonNull
        public URL toURL() {
            URL url = root.getResource(path);
            if (url == null)
                throw new RuntimeException("No resource found for path " + this);
            return url;
        }

        @Override
        public InputStream toInputStream() {
            InputStream is = root.getResourceAsStream(path);
            if (is == null)
                throw new RuntimeException("Missing resource: " + this);
            return is;
        }
    }
}
