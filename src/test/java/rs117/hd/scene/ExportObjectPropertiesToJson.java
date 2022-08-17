package rs117.hd.scene;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import rs117.hd.scene.objects.ObjectProperties;
import rs117.hd.utils.ResourcePath;

import java.io.IOException;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

import static rs117.hd.utils.ResourcePath.RESOURCE_DIR;
import static rs117.hd.utils.ResourcePath.path;

@SuppressWarnings("deprecation")
public class ExportObjectPropertiesToJson {

    public static void main(String[] args) throws IOException {

		Set<ObjectProperties> uniqueLights = new LinkedHashSet<>();
        Path configPath = ResourcePath.path(RESOURCE_DIR, "rs117/hd/scene", "objects_properties.jsonc").toPath();

        System.out.println("Loading current object Properties from JSON...");

        ObjectProperties[] currentLights = path(configPath).loadJson(ObjectProperties[].class);
        Collections.addAll(uniqueLights, currentLights);
        System.out.println("Loaded " + currentLights.length + " object Properties");

        Gson gson = new GsonBuilder().disableHtmlEscaping().setPrettyPrinting().create();

        String json = gson.toJson(uniqueLights);

        System.out.println("Writing " + uniqueLights.size() + " object Properties to JSON file: " + configPath.toAbsolutePath());
        configPath.toFile().getParentFile().mkdirs();

        OutputStreamWriter os = new OutputStreamWriter(
				Files.newOutputStream(configPath.toFile().toPath()),
                StandardCharsets.UTF_8);

        os.write(json);
        os.close();

    }

}
