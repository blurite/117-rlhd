package rs117.hd.opengl.shader;

import rs117.hd.renderer.zone.ZoneRenderer;

import static org.lwjgl.opengl.GL33C.*;

public class ParticleShaderProgram extends ShaderProgram {
	// Texture units for tiered particle textures
	// Reserve units after the scene textures, including the terrain shadows and nebula map.
	public static final int TEXTURE_UNIT_PARTICLE_64 = ZoneRenderer.TEXTURE_UNIT_TEXTURED_FACES - GL_TEXTURE0 + 1;
	public static final int TEXTURE_UNIT_PARTICLE_128 = TEXTURE_UNIT_PARTICLE_64 + 1;
	public static final int TEXTURE_UNIT_PARTICLE_256 = TEXTURE_UNIT_PARTICLE_64 + 2;
	public static final int TEXTURE_UNIT_PARTICLE_1024 = TEXTURE_UNIT_PARTICLE_64 + 3;

	private final UniformMat4 uniProjection = addUniformMat4("uProjection");
	private final UniformMat4 uniView = addUniformMat4("uView");
	private final Uniform3f uniCamPos = addUniform3f("uCamPos");
	private final UniformTexture uniParticleTex64 = addUniformTexture("particleTex64");
	private final UniformTexture uniParticleTex128 = addUniformTexture("particleTex128");
	private final UniformTexture uniParticleTex256 = addUniformTexture("particleTex256");
	private final UniformTexture uniParticleTex1024 = addUniformTexture("particleTex1024");

	public ParticleShaderProgram() {
		super(t -> t
			.add(GL_VERTEX_SHADER, "particle_vert.glsl")
			.add(GL_FRAGMENT_SHADER, "particle_frag.glsl"));
	}

	@Override
	protected void initialize() {
		uniParticleTex64.set(GL_TEXTURE0 + TEXTURE_UNIT_PARTICLE_64);
		uniParticleTex128.set(GL_TEXTURE0 + TEXTURE_UNIT_PARTICLE_128);
		uniParticleTex256.set(GL_TEXTURE0 + TEXTURE_UNIT_PARTICLE_256);
		uniParticleTex1024.set(GL_TEXTURE0 + TEXTURE_UNIT_PARTICLE_1024);
	}

	public void setProjection(float[] matrix) {
		uniProjection.set(matrix);
	}

	public void setView(float[] matrix) {
		uniView.set(matrix);
	}

	public void setCamPos(float x, float y, float z) {
		uniCamPos.set(x, y, z);
	}
}
