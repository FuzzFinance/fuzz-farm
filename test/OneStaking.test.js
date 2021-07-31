const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const FuzzToken = artifacts.require('FuzzToken');
const OneStaking = artifacts.require('OneStaking');
const MockHRC20 = artifacts.require('libs/MockHRC20');
const WONE = artifacts.require('libs/WONE');

contract('OneStaking.......', async ([alice, bob, admin, dev, minter]) => {
  beforeEach(async () => {
    this.rewardToken = await FuzzToken.new({ from: minter });
    this.lpToken = await MockHRC20.new('LPToken', 'LP1', '1000000', {
      from: minter,
    });
    this.wONE = await WONE.new({ from: minter });
    this.oneChef = await OneStaking.new(
      this.wONE.address,
      this.rewardToken.address,
      1000,
      10,
      1010,
      admin,
      this.wONE.address,
      { from: minter }
    );
    await this.rewardToken.mint(this.oneChef.address, 100000, { from: minter });
  });

  it('deposit/withdraw', async () => {
    await time.advanceBlockTo('10');
    await this.oneChef.deposit({ from: alice, value: 100 });
    await this.oneChef.deposit({ from: bob, value: 200 });
    assert.equal(
      (await this.wONE.balanceOf(this.oneChef.address)).toString(),
      '300'
    );
    assert.equal((await this.oneChef.pendingReward(alice)).toString(), '1000');
    await this.oneChef.deposit({ from: alice, value: 300 });
    assert.equal((await this.oneChef.pendingReward(alice)).toString(), '0');
    assert.equal((await this.rewardToken.balanceOf(alice)).toString(), '1333');
    await this.oneChef.withdraw('100', { from: alice });
    assert.equal(
      (await this.wONE.balanceOf(this.oneChef.address)).toString(),
      '500'
    );
    await this.oneChef.emergencyRewardWithdraw(1000, { from: minter });
    assert.equal((await this.oneChef.pendingReward(bob)).toString(), '1399');
  });

  it('should block man who in blanklist', async () => {
    await this.oneChef.setBlackList(alice, { from: admin });
    await expectRevert(
      this.oneChef.deposit({ from: alice, value: 100 }),
      'in black list'
    );
    await this.oneChef.removeBlackList(alice, { from: admin });
    await this.oneChef.deposit({ from: alice, value: 100 });
    await this.oneChef.setAdmin(dev, { from: minter });
    await expectRevert(
      this.oneChef.setBlackList(alice, { from: admin }),
      'admin: wut?'
    );
  });

  it('emergencyWithdraw', async () => {
    await this.oneChef.deposit({ from: alice, value: 100 });
    await this.oneChef.deposit({ from: bob, value: 200 });
    assert.equal(
      (await this.wONE.balanceOf(this.oneChef.address)).toString(),
      '300'
    );
    await this.oneChef.emergencyWithdraw({ from: alice });
    assert.equal(
      (await this.wONE.balanceOf(this.oneChef.address)).toString(),
      '200'
    );
    assert.equal((await this.wONE.balanceOf(alice)).toString(), '100');
  });

  it('emergencyRewardWithdraw', async () => {
    await expectRevert(
      this.oneChef.emergencyRewardWithdraw(100, { from: alice }),
      'caller is not the owner'
    );
    await this.oneChef.emergencyRewardWithdraw(1000, { from: minter });
    assert.equal((await this.rewardToken.balanceOf(minter)).toString(), '1000');
  });

  it('setLimitAmount', async () => {
    // set limit to 1e-12 BNB
    await this.oneChef.setLimitAmount('1000000', { from: minter });
    await expectRevert(
      this.oneChef.deposit({ from: alice, value: 100000000 }),
      'exceed the to'
    );
  });
});
