package rs117.hd.tests;

import com.google.gson.Gson;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Set;
import org.junit.Test;
import rs117.hd.HdPlugin;
import rs117.hd.opengl.shader.ParticleShaderProgram;
import rs117.hd.renderer.zone.ZoneRenderer;
import rs117.hd.scene.environments.Environment;

import static org.junit.Assert.*;
import static org.lwjgl.opengl.GL33C.GL_TEXTURE0;

public class CustomRenderingCompatibilityTest {
	@Test
	public void customEnvironmentAnglesSurviveDeserialization() throws Exception {
		Set<String> standardAngles = new HashSet<>(Set.of(
			"FIST_OF_GUTHIX_GAME", "FIST_OF_GUTHIX", "GAMERS_GROTTO", "STEALING_CREATIONS",
			"COCKROACH_DUNGEON", "COCKROACH_DUNGEON_PRISON", "SPIDER_REALM"));
		Set<String> verticalAngles = new HashSet<>(Set.of("SPIDER_REALM_LEVEL_FOUR", "GRIM_REAPERS_HOUSE"));
		Gson gson = new Gson();
		try (InputStream stream = getClass().getResourceAsStream("/rs117/hd/scene/environments.json")) {
			assertNotNull(stream);
			for (JsonElement entry : new JsonParser().parse(new InputStreamReader(stream, StandardCharsets.UTF_8)).getAsJsonArray()) {
				JsonObject definition = entry.getAsJsonObject();
				if (!definition.has("area"))
					continue;
				String area = definition.get("area").getAsString();
				float[] expected;
				if (standardAngles.remove(area)) {
					expected = new float[] { (float) Math.toRadians(80), (float) Math.toRadians(190) };
				} else if (verticalAngles.remove(area)) {
					expected = new float[] { (float) Math.toRadians(90), (float) Math.toRadians(90) };
				} else {
					continue;
				}
				// Area lookup requires the running client; exercise the actual lighting deserializer without it.
				definition.remove("area");
				Environment environment = gson.fromJson(definition, Environment.class).normalize();
				assertArrayEquals(area, expected, environment.getShadowAngles(), 0.00001f);
			}
		}
		assertTrue("Missing custom environments: " + standardAngles, standardAngles.isEmpty());
		assertTrue("Missing custom environments: " + verticalAngles, verticalAngles.isEmpty());
	}

	@Test
	public void particleTextureUnitsDoNotOverlapSceneBindings() throws Exception {
		Set<Integer> sceneUnits = new HashSet<>();
		for (Field field : HdPlugin.class.getFields()) {
			if (field.getName().startsWith("TEXTURE_UNIT_") && !field.getName().equals("TEXTURE_UNIT_COUNT"))
				sceneUnits.add(field.getInt(null) - GL_TEXTURE0);
		}
		sceneUnits.add(ZoneRenderer.TEXTURE_UNIT_TEXTURED_FACES - GL_TEXTURE0);
		int[] particleUnits = {
			ParticleShaderProgram.TEXTURE_UNIT_PARTICLE_64,
			ParticleShaderProgram.TEXTURE_UNIT_PARTICLE_128,
			ParticleShaderProgram.TEXTURE_UNIT_PARTICLE_256,
			ParticleShaderProgram.TEXTURE_UNIT_PARTICLE_1024
		};
		for (int unit : particleUnits) {
			assertTrue("Texture unit is shared: " + unit, sceneUnits.add(unit));
			assertTrue("Exceeds the OpenGL 3.3 minimum fragment texture-unit limit", unit < 16);
		}
	}
}
