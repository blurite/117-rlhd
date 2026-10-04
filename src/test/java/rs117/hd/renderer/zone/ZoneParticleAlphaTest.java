package rs117.hd.renderer.zone;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import rs117.hd.HdPlugin;
import rs117.hd.utils.CommandBuffer;
import rs117.hd.utils.buffer.GLMappedBufferIntWriter;

import static org.junit.Assert.*;
import static org.lwjgl.opengl.GL33C.GL_TRIANGLES;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

public class ZoneParticleAlphaTest {
	private GLMappedBufferIntWriter previousWriter;
	private boolean previousIndirectDraw;
	private Zone zone;
	private WorldViewContext context;
	private CommandBuffer commands;
	private final List<String> draws = new ArrayList<>();
	private final Zone.ParticleRenderer particles = (cmd, starts, ends, count) -> {
		for (int i = 0; i < count; i++)
			draws.add("particles:" + starts[i] + ":" + ends[i]);
	};

	@Before
	public void setUp() {
		previousWriter = ZoneRenderer.eboAlphaWriter;
		previousIndirectDraw = HdPlugin.SUPPORTS_INDIRECT_DRAW;
		ZoneRenderer.eboAlphaWriter = mock(GLMappedBufferIntWriter.class);
		HdPlugin.SUPPORTS_INDIRECT_DRAW = false;
		zone = new Zone();
		context = mock(WorldViewContext.class);
		context.maxLevel = 3;
		context.hideRoofIds = Collections.emptySet();
		commands = mock(CommandBuffer.class);
		doAnswer(invocation -> {
			draws.add("model:" + invocation.getArgument(1) + ":" + invocation.getArgument(2));
			return null;
		}).when(commands).DrawArrays(eq(GL_TRIANGLES), anyInt(), anyInt());

		// The sorted alpha list can interleave particle buckets and regular geometry.
		zone.addTempParticleModel(7, 0, 6, 0, 0, 0, 0);
		zone.addTempParticleModel(7, 6, 12, 0, 0, 0, 0);
		Zone.AlphaModel model = new Zone.AlphaModel();
		model.vao = 8;
		model.endpos = 3 * DynamicModelVAO.VERT_SIZE / Integer.BYTES;
		zone.alphaModels.add(model);
		zone.addTempParticleModel(7, 18, 24, 0, 0, 0, 0);
	}

	@After
	public void tearDown() {
		zone.postAlphaPass();
		ZoneRenderer.eboAlphaWriter = previousWriter;
		HdPlugin.SUPPORTS_INDIRECT_DRAW = previousIndirectDraw;
	}

	@Test
	public void colorPassPreservesParticleAndGeometryOrder() {
		zone.renderAlpha(commands, 0, 0, 0, context, false, false, particles);

		assertEquals(Arrays.asList("particles:0:12", "model:0:3", "particles:18:24"), draws);
		// Depth state belongs to the caller, including when rendering alpha above water.
		verify(commands, never()).DepthMask(anyBoolean());
	}

	@Test
	public void depthAndShadowPassesDrawGeometryWithoutParticles() {
		for (boolean includeRoof : new boolean[] { false, true }) {
			draws.clear();
			zone.renderAlpha(commands, 0, 0, 0, context, true, includeRoof, particles);
			assertEquals(Collections.singletonList("model:0:3"), draws);
		}
		verify(commands, never()).DepthMask(anyBoolean());
	}

	@Test
	public void missingParticleRendererStillDrawsGeometry() {
		zone.renderAlpha(commands, 0, 0, 0, context, false, false, null);

		assertEquals(Collections.singletonList("model:0:3"), draws);
	}

	@Test
	public void particleBucketsAreTemporaryAndCanBeReusedNextFrame() {
		zone.postAlphaPass();
		assertTrue(zone.alphaModels.isEmpty());
		zone.addTempParticleModel(7, 24, 30, 0, 0, 0, 0);
		zone.renderAlpha(commands, 0, 0, 0, context, false, false, particles);

		assertEquals(Collections.singletonList("particles:24:30"), draws);
		assertTrue(zone.alphaModels.get(0).isTemp());
	}
}
