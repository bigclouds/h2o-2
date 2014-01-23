package hex;

import hex.Layer.VecSoftmax;
import hex.Layer.VecsInput;
import org.junit.Assert;
import org.junit.BeforeClass;
import org.junit.Test;
import water.JUnitRunnerDebug;
import water.Key;
import water.TestUtil;
import water.UKV;
import water.fvec.Frame;
import water.fvec.NFSFileVec;
import water.fvec.ParseDataset2;
import water.fvec.Vec;
import water.util.Utils;

public class NeuralNetSpiralsTest extends TestUtil {
  @BeforeClass public static void stall() {
    stall_till_cloudsize(JUnitRunnerDebug.NODES);
  }

  @Test public void run() throws Exception {
    Key file = NFSFileVec.make(find_test_file("smalldata/neural/two_spiral.data"));
    Key parse = Key.make();
    Frame frame = ParseDataset2.parse(parse, new Key[]{file});
    UKV.remove(file);

    Vec[] data = Utils.remove(frame.vecs(), frame.vecs().length - 1);
    Vec labels = frame.vecs()[frame.vecs().length - 1];

    NeuralNet p = new NeuralNet();
    p.warmup_samples = 1000;
    p.seed = 7401699394609084302l;
    p.rate = 0.007;
    p.rate_annealing = 0;
    p.epochs = 20000;
    p.activation = NeuralNet.Activation.Tanh;
    p.max_w2 = Double.MAX_VALUE;
    p.l1 = 0;
    p.l2 = 0;
    p.momentum_start = 0;
    p.momentum_ramp = 0;
    p.momentum_stable = 0;
    p.initial_weight_distribution = NeuralNet.InitialWeightDistribution.Normal;
    p.initial_weight_scale = 2.5;

    Layer[] ls = new Layer[3];
    VecsInput input = new VecsInput(data, null);
    VecSoftmax output = new VecSoftmax(labels, null, NeuralNet.Loss.CrossEntropy);
    ls[0] = input;
    ls[1] = new Layer.Tanh(100);
    ls[2] = output;
    for( int i = 0; i < ls.length; i++ )
      ls[i].init(ls, i, p);

//    Trainer.Direct trainer = new Trainer.Direct(ls, p.epochs, null);
//    trainer.run();
    Trainer.Threaded trainer = new Trainer.Threaded(ls, p.epochs, null, -1);
    trainer.start();
    trainer.join();

    // Check that classification error is 0
    NeuralNet.Errors train = NeuralNet.eval(ls, 0, null);
    if (train.classification != 0) {
      Assert.fail("Classification error is not 0, but " + train.classification);
    }

    UKV.remove(parse);
    for( int i = 0; i < ls.length; i++ )
      ls[i].close();
  }
}
