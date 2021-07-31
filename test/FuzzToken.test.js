const { assert } = require("chai");

const FuzzToken = artifacts.require('FuzzToken');

contract('FuzzToken', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.fuzz = await FuzzToken.new({ from: minter });
    });


    it('mint', async () => {
        await this.fuzz.mint(alice, 1000, { from: minter });
        assert.equal((await this.fuzz.balanceOf(alice)).toString(), '1000');
    })
});
